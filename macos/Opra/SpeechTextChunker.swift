import Foundation

/// Keeps requests small for latency and counts Unicode scalars, as the server does.
/// Oversized PDF tokens (e.g. unbroken URLs) are split without losing their position.
enum SpeechTextChunker {
    struct Chunk {
        let text: String
        let startWordIndex: Int
        let wordCount: Int
    }

    static func split(_ text: String, limit: Int = 1_200) -> [Chunk] {
        precondition(limit > 0)
        let words = text.split(whereSeparator: { $0.isWhitespace })
        var chunks: [Chunk] = []
        var buffer = ""
        var start = 0
        var count = 0
        func flush() {
            guard !buffer.isEmpty else { return }
            chunks.append(Chunk(text: buffer, startWordIndex: start, wordCount: count))
            buffer = ""
            count = 0
        }
        for (index, word) in words.enumerated() {
            var remaining = word.unicodeScalars[...]
            if remaining.count > limit {
                flush()
                while remaining.count > limit {
                    chunks.append(Chunk(text: String(remaining.prefix(limit)), startWordIndex: index, wordCount: 0))
                    remaining = remaining.dropFirst(limit)
                }
            }
            let fragment = String(remaining)
            if !buffer.isEmpty && buffer.unicodeScalars.count + 1 + remaining.count > limit { flush() }
            if buffer.isEmpty { start = index }
            buffer += buffer.isEmpty ? fragment : " " + fragment
            count += 1
            // Prefer sentence ends once there is enough audio to amortize a request.
            if buffer.unicodeScalars.count >= min(500, limit / 2), let last = fragment.last, ".!?".contains(last) { flush() }
        }
        flush()
        return chunks
    }
}
