import Foundation

enum TaskRoute: Hashable {
    case detail(UUID)
}

/// Формы дела открываются модальным листом.
enum TaskSheet: Identifiable, Hashable {
    case create(Date)
    /// Дело, разобранное из голосовой фразы: поля уже заполнены.
    case createFromVoice(VoiceTaskResult)
    /// Правка только этого выполнения.
    case edit(UUID)
    /// Явная правка всей серии.
    case editSeries(UUID)

    var id: String {
        switch self {
        case .create(let date): "create-\(date.timeIntervalSince1970)"
        case .createFromVoice(let result): "create-voice-\(result.draft.title)-\(result.draft.start.timeIntervalSince1970)"
        case .edit(let id): "edit-\(id)"
        case .editSeries(let id): "series-\(id)"
        }
    }
}

enum TaskFilter: Hashable {
    case all
    case mine
    case member(UUID)
}
