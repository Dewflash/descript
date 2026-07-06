import AppKit
import Foundation
import SwiftUI

enum TranscriptSource: String, CaseIterable, Identifiable {
    case youtube
    case mp4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .youtube: "YouTube"
        case .mp4: "MP4"
        }
    }
}

enum Accent: String, CaseIterable, Identifiable {
    case emerald
    case violet
    case amber
    case cyan
    case rose
    case lime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emerald: "Green"
        case .violet: "Purple"
        case .amber: "Amber"
        case .cyan: "Cyan"
        case .rose: "Rose"
        case .lime: "Lime"
        }
    }

    var color: Color {
        switch self {
        case .emerald: Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
        case .violet: Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255)
        case .amber: Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
        case .cyan: Color(red: 34 / 255, green: 211 / 255, blue: 238 / 255)
        case .rose: Color(red: 244 / 255, green: 63 / 255, blue: 94 / 255)
        case .lime: Color(red: 163 / 255, green: 230 / 255, blue: 53 / 255)
        }
    }

    var foreground: Color {
        switch self {
        case .violet, .rose: .white
        case .emerald, .amber, .cyan, .lime: .black
        }
    }
}

@MainActor
final class DescriptModel: ObservableObject {
    @Published var source: TranscriptSource = .youtube
    @Published var youtubeURL = ""
    @Published var notes = ""
    @Published var transcript = "Paste a YouTube URL or choose an MP4. The extracted transcript lands here."
    @Published var statusText = "YouTube · 0 words"
    @Published var selectedFileName: String?
    @Published var isBusy = false
    @Published var isShowingSettings = false
    @Published var youtubeAccent: Accent
    @Published var mp4Accent: Accent

    private let defaults = UserDefaults.standard

    init() {
        youtubeAccent = Accent(rawValue: defaults.string(forKey: "youtubeAccent") ?? "") ?? .emerald
        mp4Accent = Accent(rawValue: defaults.string(forKey: "mp4Accent") ?? "") ?? .violet
    }

    var activeAccent: Accent {
        accent(for: source)
    }

    func accent(for source: TranscriptSource) -> Accent {
        switch source {
        case .youtube: youtubeAccent
        case .mp4: mp4Accent
        }
    }

    func setAccent(_ accent: Accent, for source: TranscriptSource) {
        switch source {
        case .youtube:
            youtubeAccent = accent
            defaults.set(accent.rawValue, forKey: "youtubeAccent")
        case .mp4:
            mp4Accent = accent
            defaults.set(accent.rawValue, forKey: "mp4Accent")
        }
    }

    func pasteClipboardToYouTube() {
        youtubeURL = NSPasteboard.general.string(forType: .string) ?? ""
    }

    func extractYouTube() {
        guard !isBusy else { return }
        let input = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            showError("Paste or type a YouTube URL first.")
            return
        }

        source = .youtube
        isBusy = true
        statusText = "YouTube · extracting"

        Task {
            do {
                let text = try await YouTubeTranscriptService.fetchTranscript(from: input)
                transcript = text
                statusText = "YouTube · \(wordCount(text)) words"
                copyToClipboard(text)
            } catch {
                showError(error.localizedDescription)
                statusText = "YouTube · failed"
            }
            isBusy = false
        }
    }

    func chooseMP4() {
        guard !isBusy else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose an MP4 video to transcribe"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        source = .mp4
        selectedFileName = url.lastPathComponent
        isBusy = true
        statusText = "MP4 · transcribing"

        Task {
            do {
                let audioURL = try await AudioExtractor.exportAudio(from: url)
                defer { try? FileManager.default.removeItem(at: audioURL) }

                let text = try await SpeechTranscriber.transcribe(url: audioURL)
                transcript = text
                statusText = "MP4 · \(wordCount(text)) words"
                copyToClipboard(text)
            } catch {
                showError(error.localizedDescription)
                statusText = "MP4 · failed"
            }
            isBusy = false
        }
    }

    func copyTranscript() {
        copyToClipboard(transcript)
    }

    func saveTranscript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcript.txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try transcript.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Descript"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func wordCount(_ value: String) -> Int {
        value.split { $0.isWhitespace || $0.isNewline }.count
    }
}
