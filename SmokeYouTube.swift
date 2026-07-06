import Foundation

@main
struct SmokeYouTube {
    static func main() async {
        do {
            let transcript = try await YouTubeTranscriptService.fetchTranscript(
                from: "https://www.youtube.com/watch?v=dg9Ezg_RS6E"
            )
            let words = transcript.split { $0.isWhitespace || $0.isNewline }.count
            print("OK words=\(words)")
            print(String(transcript.prefix(500)))
        } catch {
            print("ERROR \(type(of: error)): \(error.localizedDescription)")
            exit(1)
        }
    }
}
