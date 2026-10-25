import Foundation

enum TaskRoute: Hashable {
    case detail(UUID)
    case create(Date)
    /// Правка только этого выполнения.
    case edit(UUID)
    /// Явная правка всей серии.
    case editSeries(UUID)
}

enum TaskFilter: Equatable {
    case all
    case mine
    case member(UUID)
}
