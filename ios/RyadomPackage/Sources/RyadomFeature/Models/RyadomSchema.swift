import SwiftData

public enum RyadomSchema {
    public static let models: [any PersistentModel.Type] = [
        FamilyRecord.self, MemberRecord.self,
        ShoppingListRecord.self, ShoppingItemRecord.self,
        TaskSeriesRecord.self, TaskOccurrenceRecord.self, ChecklistItemRecord.self,
        DocumentRecord.self, OutboxOperation.self, SyncCursor.self,
    ]

    public static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Не удалось создать локальную базу: \(error)")
        }
    }
}
