import Foundation

@main
struct SmokeYouTube {
    static func main() async {
        let url = ProcessInfo.processInfo.environment["DESCRIPT_SMOKE_URL"]
            ?? "https://www.youtube.com/watch?v=dg9Ezg_RS6E"
        do {
            let transcript = try await YouTubeTranscriptService.fetchTranscript(from: url)
            let words = transcript.split { $0.isWhitespace || $0.isNewline }.count
            guard words >= 50 else {
                print("ERROR transcript too short: words=\(words)")
                exit(1)
            }
            print("OK words=\(words)")
            print(String(transcript.prefix(500)))
        } catch {
            print("ERROR \(type(of: error)): \(error.localizedDescription)")
            exit(1)
        }
    }
}
