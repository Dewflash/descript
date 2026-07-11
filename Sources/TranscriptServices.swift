import AVFoundation
import Foundation
import Speech
import UniformTypeIdentifiers

enum DescriptError: LocalizedError {
    case invalidYouTubeURL
    case missingCaptionTracks
    case unsupportedTranscriptURL(String)
    case noTranscriptText
    case youtubeRequestFailed(String)
    case audioExportFailed(String)
    case speechUnavailable
    case speechPermissionDenied
    case speechRecognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidYouTubeURL:
            "That does not look like a valid YouTube URL."
        case .missingCaptionTracks:
            "No transcript track was found for this YouTube video."
        case .unsupportedTranscriptURL(let detail):
            "YouTube returned a transcript URL this app could not read: \(detail)"
        case .noTranscriptText:
            "No transcript text was returned."
        case .youtubeRequestFailed(let detail):
            "YouTube transcript request failed: \(detail)"
        case .audioExportFailed(let detail):
            "Audio export failed: \(detail)"
        case .speechUnavailable:
            "On-device speech recognition is not available on this Mac."
        case .speechPermissionDenied:
            "Enable Speech Recognition in System Settings > Privacy & Security."
        case .speechRecognitionFailed(let detail):
            "Speech recognition failed: \(detail)"
        }
    }
}

struct YouTubeTranscriptService {
    private static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"
    private static let androidClientContext: [String: Any] = [
        "client": [
            "clientName": "ANDROID",
            "clientVersion": "20.10.38"
        ]
    ]

    static func fetchTranscript(from input: String) async throws -> String {
        let videoID = try extractVideoID(from: input)
        let html = try await fetchWatchHTML(videoID: videoID)

        var androidPlayerError: Error?
        if let apiKey = firstRegexCapture(#""INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)""#, in: html) {
            do {
                if let text = try await fetchTranscriptViaAndroidPlayer(videoID: videoID, apiKey: apiKey) {
                    return text
                }
            } catch {
                androidPlayerError = error
            }
        }

        guard let tracks = captionTracks(fromHTML: html) else {
            throw androidPlayerError ?? DescriptError.missingCaptionTracks
        }

        guard let text = try await fetchTranscript(fromTracks: tracks) else {
            throw androidPlayerError ?? DescriptError.noTranscriptText
        }

        return text
    }

    private static func fetchWatchHTML(videoID: String) async throws -> String {
        let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        var request = URLRequest(url: watchURL)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-GB,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        try assertSuccessfulHTTP(response)

        guard let html = String(data: data, encoding: .utf8) else {
            throw DescriptError.youtubeRequestFailed("Could not decode the YouTube watch page.")
        }

        return html
    }

    private static func fetchTranscriptViaAndroidPlayer(videoID: String, apiKey: String) async throws -> String? {
        let url = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(apiKey)")!
        let body: [String: Any] = [
            "context": androidClientContext,
            "videoId": videoID
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try assertSuccessfulHTTP(response)

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DescriptError.youtubeRequestFailed("Could not parse Android player response.")
        }

        if let status = (object["playabilityStatus"] as? [String: Any])?["status"] as? String,
           status != "OK" {
            let reason = (object["playabilityStatus"] as? [String: Any])?["reason"] as? String ?? status
            throw DescriptError.youtubeRequestFailed(reason)
        }

        guard let tracks = ((object["captions"] as? [String: Any])?["playerCaptionsTracklistRenderer"] as? [String: Any])?["captionTracks"] as? [[String: Any]] else {
            return nil
        }

        return try await fetchTranscript(fromTracks: tracks)
    }

    private static func captionTracks(fromHTML html: String) -> [[String: Any]]? {
        guard let tracksJSON = jsonArray(after: "\"captionTracks\":", in: html),
              let tracksData = tracksJSON.data(using: .utf8),
              let tracks = try? JSONSerialization.jsonObject(with: tracksData) as? [[String: Any]] else {
            return nil
        }

        return tracks
    }

    private static func fetchTranscript(fromTracks tracks: [[String: Any]]) async throws -> String? {
        for track in orderedCaptionTracks(tracks) {
            guard let baseURL = track["baseUrl"] as? String else {
                continue
            }

            for url in try captionURLVariants(from: baseURL) {
                if let text = try await fetchTranscriptText(from: url) {
                    return text
                }
            }
        }

        return nil
    }

    private static func orderedCaptionTracks(_ tracks: [[String: Any]]) -> [[String: Any]] {
        tracks.sorted { left, right in
            scoreCaptionTrack(left) < scoreCaptionTrack(right)
        }
    }

    private static func scoreCaptionTrack(_ track: [String: Any]) -> Int {
        let language = (track["languageCode"] as? String)?.lowercased() ?? ""
        let isEnglish = language == "en" || language.hasPrefix("en-")
        let isGenerated = (track["kind"] as? String) == "asr"

        switch (isEnglish, isGenerated) {
        case (true, false): return 0
        case (true, true): return 1
        case (false, false): return 2
        case (false, true): return 3
        }
    }

    private static func captionURLVariants(from baseURL: String) throws -> [URL] {
        var variants: [URL] = []

        func append(_ value: String) throws {
            let url = try normalizedCaptionURL(from: value)
            if !variants.contains(url) {
                variants.append(url)
            }
        }

        if baseURL.contains("&fmt=srv3") {
            try append(baseURL.replacingOccurrences(of: "&fmt=srv3", with: ""))
        }

        try append(baseURL)

        if !baseURL.contains("fmt=") {
            let separator = baseURL.contains("?") ? "&" : "?"
            try append("\(baseURL)\(separator)fmt=json3")
            try append("\(baseURL)\(separator)fmt=srv3")
        }

        return variants
    }

    private static func fetchTranscriptText(from url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-GB,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        try assertSuccessfulHTTP(response)

        guard !data.isEmpty else {
            return nil
        }

        guard let rawText = String(data: data, encoding: .utf8) else {
            return nil
        }

        let parsedText: String
        if rawText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            parsedText = parseJSON3Transcript(data: data)
        } else {
            parsedText = TranscriptXMLParser().parse(data: data)
        }

        let normalized = normalize(parsedText)
        return normalized.isEmpty ? nil : normalized
    }

    private static func parseJSON3Transcript(data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = object["events"] as? [[String: Any]] else {
            return ""
        }

        let parts = events.flatMap { event -> [String] in
            guard let segments = event["segs"] as? [[String: Any]] else {
                return []
            }

            return segments.compactMap { segment in
                guard let text = segment["utf8"] as? String else {
                    return nil
                }
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
        }

        return parts.joined(separator: " ")
    }

    private static func assertSuccessfulHTTP(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DescriptError.youtubeRequestFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    private static func firstRegexCapture(_ pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: source) else {
            return nil
        }

        return String(source[captureRange])
    }

    private static func extractVideoID(from input: String) throws -> String {
        let trimmed = sanitizeInput(input)
        if trimmed.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil {
            return trimmed
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let rawHost = components.host?.lowercased() else {
            throw DescriptError.invalidYouTubeURL
        }

        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if host == "youtu.be" {
            let id = components.path.split(separator: "/").first.map(String.init) ?? ""
            if isValidVideoID(id) { return id }
        }

        if ["youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com"].contains(host) {
            if let id = components.queryItems?.first(where: { $0.name == "v" })?.value, isValidVideoID(id) {
                return id
            }

            let parts = components.path.split(separator: "/").map(String.init)
            if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]), isValidVideoID(parts[1]) {
                return parts[1]
            }
        }

        throw DescriptError.invalidYouTubeURL
    }

    private static func sanitizeInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") {
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let range = trimmed.range(of: #"https?://[^\s<>)"]+"#, options: .regularExpression) {
            return String(trimmed[range])
        }

        return trimmed
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }

    private static func normalizedCaptionURL(from baseURL: String) throws -> URL {
        let unescaped = baseURL
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&")
            .replacingOccurrences(of: #"\u0026"#, with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")

        let candidate: String
        if unescaped.hasPrefix("//") {
            candidate = "https:\(unescaped)"
        } else if unescaped.hasPrefix("/") {
            candidate = "https://www.youtube.com\(unescaped)"
        } else if unescaped.hasPrefix("api/") {
            candidate = "https://www.youtube.com/\(unescaped)"
        } else {
            candidate = unescaped
        }

        guard let components = URLComponents(string: candidate),
              let url = components.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw DescriptError.unsupportedTranscriptURL(candidate)
        }

        return url
    }

    private static func jsonArray(after marker: String, in source: String) -> String? {
        guard let markerRange = source.range(of: marker),
              let start = source[markerRange.upperBound...].firstIndex(of: "[") else {
            return nil
        }

        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start

        while index < source.endIndex {
            let character = source[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        return String(source[start...index])
                    }
                }
            }

            index = source.index(after: index)
        }

        return nil
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class TranscriptXMLParser: NSObject, XMLParserDelegate {
    private var values: [String] = []
    private var current = ""
    private var isReadingText = false
    private var isReadingParagraph = false

    func parse(data: Data) -> String {
        values = []
        current = ""
        isReadingText = false
        isReadingParagraph = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return values.joined(separator: " ")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "text" {
            isReadingText = true
            current = ""
        } else if elementName == "p" {
            isReadingParagraph = true
            current = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isReadingText || isReadingParagraph else { return }
        current += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "text" || elementName == "p" else { return }
        let cleaned = decodeHTMLEntities(current.trimmingCharacters(in: .whitespacesAndNewlines))
        if !cleaned.isEmpty {
            values.append(cleaned)
        }
        current = ""
        if elementName == "text" {
            isReadingText = false
        } else {
            isReadingParagraph = false
        }
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        var decoded = value
        for _ in 0..<2 {
            decoded = decoded
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#34;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        return decoded
    }
}

struct AudioExtractor {
    static func exportAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw DescriptError.audioExportFailed("Apple M4A export is not available for this file.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("descript-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        export.outputURL = outputURL
        export.outputFileType = .m4a

        return try await withCheckedThrowingContinuation { continuation in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed, .cancelled:
                    continuation.resume(throwing: DescriptError.audioExportFailed(export.error?.localizedDescription ?? "Unknown export error."))
                default:
                    continuation.resume(throwing: DescriptError.audioExportFailed("Unexpected export status."))
                }
            }
        }
    }
}

struct SpeechTranscriber {
    static func transcribe(url: URL) async throws -> String {
        try await requestAuthorization()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw DescriptError.speechUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(throwing: DescriptError.speechRecognitionFailed(error.localizedDescription))
                    return
                }

                guard let result, result.isFinal else { return }
                let text = result.bestTranscription.formattedString
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !didResume else { return }
                didResume = true
                if text.isEmpty {
                    continuation.resume(throwing: DescriptError.noTranscriptText)
                } else {
                    continuation.resume(returning: text)
                }
            }

            _ = task
        }
    }

    private static func requestAuthorization() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return }

        let newStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard newStatus == .authorized else {
            throw DescriptError.speechPermissionDenied
        }
    }
}
