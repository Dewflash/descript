import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
import wave
from datetime import datetime
from urllib.parse import parse_qs, urlparse

import pyperclip
import rumps
from pydub import AudioSegment
from youtube_transcript_api import YouTubeTranscriptApi


APP_NAME = "Transcript Extractor"
MENU_TITLE = "📜"
YOUTUBE_LANGUAGES = ["en", "en-US", "en-GB"]
HOMEBREW_PATHS = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]


def notify_success(title, message):
    rumps.notification(APP_NAME, title, message)


def notify_error(title, message):
    rumps.notification(APP_NAME, title, message)


def normalize_transcript_text(text):
    return re.sub(r"\s+", " ", text.replace("\n", " ")).strip()


def transcript_entries_to_paragraph(entries):
    parts = []
    for entry in entries:
        if isinstance(entry, dict):
            text = entry.get("text", "")
        else:
            text = getattr(entry, "text", "")
        text = normalize_transcript_text(str(text))
        if text:
            parts.append(text)
    return normalize_transcript_text(" ".join(parts))


def extract_youtube_video_id(value):
    value = value.strip()
    if re.fullmatch(r"[A-Za-z0-9_-]{11}", value):
        return value

    parsed = urlparse(value)
    host = parsed.netloc.lower().replace("www.", "")
    path_parts = [part for part in parsed.path.split("/") if part]

    if host in {"youtube.com", "m.youtube.com", "music.youtube.com"}:
        query_id = parse_qs(parsed.query).get("v", [None])[0]
        if query_id and re.fullmatch(r"[A-Za-z0-9_-]{11}", query_id):
            return query_id
        if len(path_parts) >= 2 and path_parts[0] in {"shorts", "embed", "live"}:
            candidate = path_parts[1]
            if re.fullmatch(r"[A-Za-z0-9_-]{11}", candidate):
                return candidate

    if host == "youtu.be" and path_parts:
        candidate = path_parts[0]
        if re.fullmatch(r"[A-Za-z0-9_-]{11}", candidate):
            return candidate

    return None


def fetch_youtube_transcript(video_id):
    if hasattr(YouTubeTranscriptApi, "get_transcript"):
        return YouTubeTranscriptApi.get_transcript(video_id, languages=YOUTUBE_LANGUAGES)

    api = YouTubeTranscriptApi()
    fetched = api.fetch(video_id, languages=YOUTUBE_LANGUAGES)
    if hasattr(fetched, "to_raw_data"):
        return fetched.to_raw_data()
    return list(fetched)


def choose_mp4_with_applescript():
    script = """
        set selectedFile to choose file with prompt "Select an MP4 video to transcribe" of type {"mp4", "public.mpeg-4"}
        return POSIX path of selectedFile
    """
    completed = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        error_text = (completed.stderr or completed.stdout or "").strip()
        if "User canceled" in error_text:
            return None
        raise RuntimeError(error_text or "The file picker could not be opened.")

    selected_path = completed.stdout.strip()
    if not selected_path:
        return None
    if not selected_path.lower().endswith(".mp4"):
        raise RuntimeError("Please choose a .mp4 file.")
    return selected_path


def configure_ffmpeg_for_gui_app():
    current_path = os.environ.get("PATH", "")
    os.environ["PATH"] = os.pathsep.join(HOMEBREW_PATHS + [current_path])

    ffmpeg_path = shutil.which("ffmpeg")
    ffprobe_path = shutil.which("ffprobe")
    if not ffmpeg_path or not ffprobe_path:
        raise RuntimeError(
            "ffmpeg and ffprobe were not found. Install them with: brew install ffmpeg"
        )

    AudioSegment.converter = ffmpeg_path
    AudioSegment.ffmpeg = ffmpeg_path
    AudioSegment.ffprobe = ffprobe_path


def format_nserror(error):
    if error is None:
        return ""
    if hasattr(error, "localizedDescription"):
        return str(error.localizedDescription())
    return str(error)


def pump_current_run_loop_until(done_event, timeout_seconds, timeout_message):
    from Foundation import NSDate, NSDefaultRunLoopMode, NSRunLoop

    deadline = time.monotonic() + timeout_seconds
    run_loop = NSRunLoop.currentRunLoop()

    while not done_event.is_set():
        if time.monotonic() >= deadline:
            raise TimeoutError(timeout_message)
        run_loop.runMode_beforeDate_(
            NSDefaultRunLoopMode,
            NSDate.dateWithTimeIntervalSinceNow_(0.1),
        )


def request_speech_authorization():
    import Speech

    done = threading.Event()
    state = {}

    def authorization_handler(status):
        state["status"] = int(status)
        done.set()

    Speech.SFSpeechRecognizer.requestAuthorization_(authorization_handler)
    pump_current_run_loop_until(
        done,
        timeout_seconds=60,
        timeout_message="Speech recognition permission was not granted in time.",
    )

    authorized = int(
        getattr(Speech, "SFSpeechRecognizerAuthorizationStatusAuthorized", 3)
    )
    denied = int(getattr(Speech, "SFSpeechRecognizerAuthorizationStatusDenied", 1))
    restricted = int(
        getattr(Speech, "SFSpeechRecognizerAuthorizationStatusRestricted", 2)
    )

    status = state.get("status")
    if status == authorized:
        return
    if status == denied:
        raise PermissionError(
            "Speech recognition permission was denied. Enable it in System Settings > Privacy & Security > Speech Recognition."
        )
    if status == restricted:
        raise PermissionError("Speech recognition is restricted on this Mac.")
    raise PermissionError("Speech recognition permission was not granted.")


def transcribe_audio_url_offline(audio_path):
    import Speech
    from Foundation import NSLocale, NSURL

    request_speech_authorization()

    recognizer = Speech.SFSpeechRecognizer.alloc().initWithLocale_(
        NSLocale.localeWithLocaleIdentifier_("en_US")
    )
    if recognizer is None:
        raise RuntimeError("SFSpeechRecognizer could not be initialized.")
    if hasattr(recognizer, "isAvailable") and not recognizer.isAvailable():
        raise RuntimeError("SFSpeechRecognizer is not currently available.")
    if hasattr(recognizer, "supportsOnDeviceRecognition"):
        if not recognizer.supportsOnDeviceRecognition():
            raise RuntimeError(
                "On-device speech recognition is not available for the selected locale."
            )

    audio_url = NSURL.fileURLWithPath_(audio_path)
    request = Speech.SFSpeechURLRecognitionRequest.alloc().initWithURL_(audio_url)
    if request is None:
        raise RuntimeError("SFSpeechURLRecognitionRequest could not be created.")
    if not hasattr(request, "setRequiresOnDeviceRecognition_"):
        raise RuntimeError(
            "This macOS Speech framework does not expose required offline recognition."
        )

    request.setRequiresOnDeviceRecognition_(True)
    if hasattr(request, "setShouldReportPartialResults_"):
        request.setShouldReportPartialResults_(False)

    done = threading.Event()
    state = {"text": "", "task": None}

    def result_handler(result, error):
        if error is not None:
            state["error"] = format_nserror(error)
            done.set()
            return

        if result is not None:
            best_transcription = result.bestTranscription()
            if best_transcription is not None:
                state["text"] = str(best_transcription.formattedString())
            if result.isFinal():
                done.set()

    task = recognizer.recognitionTaskWithRequest_resultHandler_(request, result_handler)
    state["task"] = task

    timeout_seconds = max(300, int(wav_duration_seconds(audio_path) * 4) + 60)
    try:
        pump_current_run_loop_until(
            done,
            timeout_seconds=timeout_seconds,
            timeout_message="Offline transcription timed out.",
        )
    except Exception:
        if task is not None and hasattr(task, "cancel"):
            task.cancel()
        raise

    if state.get("error"):
        raise RuntimeError(state["error"])

    transcript = normalize_transcript_text(state.get("text", ""))
    if not transcript:
        raise RuntimeError("No speech was recognized in the selected MP4.")
    return transcript


def wav_duration_seconds(wav_path):
    with wave.open(wav_path, "rb") as wav_file:
        frame_count = wav_file.getnframes()
        frame_rate = wav_file.getframerate()
    if frame_rate <= 0:
        return 0
    return frame_count / float(frame_rate)


def export_mp4_audio_to_wav(mp4_path):
    configure_ffmpeg_for_gui_app()

    temp_file = tempfile.NamedTemporaryFile(prefix="transcript-audio-", suffix=".wav", delete=False)
    temp_file.close()

    try:
        audio = AudioSegment.from_file(mp4_path, format="mp4")
        audio = audio.set_channels(1).set_frame_rate(16000)
        audio.export(temp_file.name, format="wav")
        return temp_file.name
    except Exception:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        raise


def transcript_output_path_for(mp4_path):
    root, _ = os.path.splitext(mp4_path)
    candidate = f"{root}.transcript.txt"
    if not os.path.exists(candidate):
        return candidate

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return f"{root}.transcript-{timestamp}.txt"


class TranscriptExtractorApp(rumps.App):
    def __init__(self):
        super().__init__(MENU_TITLE, quit_button=None)
        self.local_worker_lock = threading.Lock()
        self.menu = [
            rumps.MenuItem(
                "Extract YouTube Transcript from Clipboard",
                callback=self.extract_youtube_from_clipboard,
            ),
            rumps.MenuItem("Transcribe Local MP4...", callback=self.transcribe_local_mp4),
            None,
            rumps.MenuItem("Quit", callback=lambda _: rumps.quit_application()),
        ]

    def extract_youtube_from_clipboard(self, _):
        try:
            clipboard_value = pyperclip.paste().strip()
            if not clipboard_value:
                raise ValueError("The clipboard is empty.")

            video_id = extract_youtube_video_id(clipboard_value)
            if not video_id:
                raise ValueError("The clipboard does not contain a valid YouTube URL.")

            entries = fetch_youtube_transcript(video_id)
            transcript = transcript_entries_to_paragraph(entries)
            if not transcript:
                raise RuntimeError("No transcript text was returned for this video.")

            pyperclip.copy(transcript)
            notify_success(
                "YouTube transcript copied",
                f"Copied {len(transcript.split())} words to the clipboard.",
            )
        except Exception as exc:
            notify_error("YouTube extraction failed", str(exc))

    def transcribe_local_mp4(self, _):
        if not self.local_worker_lock.acquire(blocking=False):
            notify_error(
                "Transcription already running",
                "Wait for the current MP4 transcription to finish.",
            )
            return

        try:
            mp4_path = choose_mp4_with_applescript()
            if not mp4_path:
                self.local_worker_lock.release()
                return
        except Exception as exc:
            self.local_worker_lock.release()
            notify_error("File selection failed", str(exc))
            return

        notify_success("Transcription started", os.path.basename(mp4_path))
        worker = threading.Thread(
            target=self._transcribe_local_mp4_worker,
            args=(mp4_path,),
            daemon=True,
        )
        worker.start()

    def _transcribe_local_mp4_worker(self, mp4_path):
        wav_path = None
        try:
            wav_path = export_mp4_audio_to_wav(mp4_path)
            transcript = transcribe_audio_url_offline(wav_path)
            output_path = transcript_output_path_for(mp4_path)
            with open(output_path, "w", encoding="utf-8") as output_file:
                output_file.write(transcript + "\n")

            pyperclip.copy(transcript)
            notify_success(
                "MP4 transcription complete",
                f"Saved transcript and copied it to the clipboard: {os.path.basename(output_path)}",
            )
        except Exception as exc:
            notify_error("MP4 transcription failed", str(exc))
        finally:
            if wav_path and os.path.exists(wav_path):
                os.unlink(wav_path)
            self.local_worker_lock.release()


if __name__ == "__main__":
    TranscriptExtractorApp().run()
