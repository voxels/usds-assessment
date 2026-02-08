import Foundation

struct TagExtractor: Sendable {

    nonisolated static func extractTags(from text: String, count: Int = 5) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
            "her", "was", "one", "our", "out", "has", "have", "been", "some",
            "them", "than", "its", "over", "such", "that", "this", "with", "will",
            "each", "from", "they", "been", "said", "into", "more", "other",
            "which", "their", "about", "would", "these", "could", "after",
            "shall", "under", "before", "those", "since", "where", "being",
            "through", "between", "should", "during", "without", "including",
            "also", "section", "part", "title", "chapter", "agency", "federal",
            "regulation", "regulations", "code", "paragraph", "subpart"
        ]
        
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }

        var frequency: [String: Int] = [:]
        for word in words {
            frequency[word, default: 0] += 1
        }

        return frequency
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { $0.key.capitalized }
    }
}

