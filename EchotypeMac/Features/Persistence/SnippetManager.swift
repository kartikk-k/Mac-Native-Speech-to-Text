//
//  SnippetManager.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/9/26.
//

import Foundation

struct Snippet: Identifiable, Codable {
    var id = UUID()
    var trigger: String    // what the user says, e.g. "my email address"
    var replacement: String // what gets inserted, e.g. "hello@example.com"
}

@Observable
final class SnippetManager {
    var snippets: [Snippet] = []

    private static let storageKey = "savedSnippets"

    init() {
        load()
    }

    func add(trigger: String, replacement: String) {
        let snippet = Snippet(trigger: trigger, replacement: replacement)
        snippets.append(snippet)
        save()
    }

    func delete(at offsets: IndexSet) {
        for offset in offsets.sorted().reversed() {
            snippets.remove(at: offset)
        }
        save()
    }

    func delete(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    func update(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
            save()
        }
    }

    /// Apply all snippets to transcribed text (case-insensitive matching).
    func applySnippets(to text: String) -> String {
        var result = text
        for snippet in snippets {
            guard !snippet.trigger.isEmpty else { continue }
            // Case-insensitive replacement
            if result.range(of: snippet.trigger, options: .caseInsensitive) != nil {
                result = result.replacingOccurrences(
                    of: snippet.trigger,
                    with: snippet.replacement,
                    options: .caseInsensitive
                )
            }
        }
        return result
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return }
        snippets = decoded
    }
}
