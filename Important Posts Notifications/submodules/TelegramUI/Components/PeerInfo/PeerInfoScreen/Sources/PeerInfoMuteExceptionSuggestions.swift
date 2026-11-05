import Foundation
import TelegramCore

// Локальные концепты: подсказки слов из поста для экрана исключений. Редактор один
// (PeerInfoMuteExceptionsScreen.swift); при открытии из меню поста слова этого поста показываются
// в ячейке ключевых слов серыми контурными фишками — нажатие добавляет слово.

private let stopWords: Set<String> = [
    "the", "and", "for", "with", "that", "this", "are", "was", "has", "have", "from", "into", "will", "after",
    "about", "over", "than", "then", "what", "when", "where", "which", "their", "them", "they", "you", "your",
    "our", "its", "not", "but", "can", "new", "all", "out", "one", "now", "just", "more", "also", "been",
    "что", "это", "как", "для", "при", "его", "она", "они", "все", "так", "или", "уже", "был", "была", "были",
    "будет", "если", "только", "также", "после", "этом", "этого", "между", "более", "около", "про", "над", "под"
]

/// Слова из текста поста, которые стоит предложить: сначала тикеры (ЗАГЛАВНЫМИ) и имена с большой
/// буквы, затем остальные; без служебных слов и повторов.
func muteExceptionSuggestedWords(from text: String, limit: Int = 8) -> [String] {
    var seen = Set<String>()
    var candidates: [(word: String, score: Int, position: Int)] = []
    let parts = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    for (position, part) in parts.enumerated() {
        let key = part.lowercased()
        if part.count < 2 || part.count > 24 || stopWords.contains(key) || seen.contains(key) || Int(part) != nil {
            continue
        }
        seen.insert(key)
        let isUpper = part.count >= 2 && part == part.uppercased() && part != part.lowercased()
        let isCapitalized = part.first.map { String($0) == String($0).uppercased() && String($0) != String($0).lowercased() } ?? false
        let score: Int
        if isUpper {
            score = 3
        } else if isCapitalized && position != 0 {
            score = 2
        } else if part.count >= 4 {
            score = 1
        } else {
            continue
        }
        candidates.append((part, score, position))
    }
    candidates.sort { lhs, rhs in
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.position < rhs.position
    }
    return Array(candidates.prefix(limit).map { $0.word })
}
