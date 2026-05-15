import Foundation

final class ContentFilterService: @unchecked Sendable {
    private let repository: ContentFilterRepository

    init(repository: ContentFilterRepository) {
        self.repository = repository
    }

    func rules(bookID: UUID) async throws -> [ContentFilterRule] {
        try await Task.detached(priority: .utility) { [repository] in
            try repository.fetchRules(bookID: bookID)
        }.value
    }

    func addRule(bookID: UUID, sourceText: String, replacementText: String?) async throws -> ContentFilterRule {
        try await Task.detached(priority: .utility) { [repository] in
            try repository.insertRule(bookID: bookID, sourceText: sourceText, replacementText: replacementText)
        }.value
    }

    func deleteRule(_ rule: ContentFilterRule) async throws {
        try await Task.detached(priority: .utility) { [repository] in
            try repository.deleteRule(rule)
        }.value
    }

    func applyRules(_ rules: [ContentFilterRule], to text: String) -> String {
        guard !rules.isEmpty, !text.isEmpty else {
            return text
        }

        var filteredText = text
        for rule in rules where !rule.sourceText.isEmpty {
            filteredText = filteredText.replacingOccurrences(
                of: rule.sourceText,
                with: rule.replacementText ?? "",
                options: [.caseInsensitive]
            )
        }
        return filteredText
    }
}
