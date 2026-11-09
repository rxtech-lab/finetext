import Foundation
import SwiftData

enum HistoryStore {
  @MainActor static func page(in context: ModelContext, query: String, offset: Int) throws -> [RefinementSession] {
    let nonempty = #Predicate<RefinementSession> {
      !$0.originalText.isEmpty || !$0.rewrites.isEmpty || !$0.translations.isEmpty || !$0.images.isEmpty
    }
    let original = #Predicate<RefinementSession> { $0.originalText.localizedStandardContains(query) }
    let title = #Predicate<RefinementSession> { $0.summaryTitle.localizedStandardContains(query) }
    let rewrites = #Predicate<RefinementSession> { $0.rewrites.contains { $0.output.localizedStandardContains(query) } }
    let translations = #Predicate<RefinementSession> { $0.translations.contains { $0.output.localizedStandardContains(query) } }
    let images = #Predicate<RefinementSession> { $0.images.contains { $0.instruction.localizedStandardContains(query) } }
    let matches = #Predicate<RefinementSession> {
      original.evaluate($0) || title.evaluate($0) || rewrites.evaluate($0) || translations.evaluate($0) || images.evaluate($0)
    }
    let predicate = query.isEmpty ? nonempty : #Predicate<RefinementSession> {
      nonempty.evaluate($0) && matches.evaluate($0)
    }
    var descriptor = FetchDescriptor<RefinementSession>(predicate: predicate, sortBy: [
      SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)
    ])
    descriptor.fetchLimit = 20
    descriptor.fetchOffset = offset
    return try context.fetch(descriptor)
  }
}
