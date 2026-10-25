import SwiftUI
import SwiftData
import RyadomFeature

@main
struct RyadomApp: App {
    private let container: ModelContainer

    init() {
        #if DEBUG
        if DemoData.isRequested {
            container = RyadomSchema.makeContainer(inMemory: true)
            DemoData.seed(into: container.mainContext)
            return
        }
        #endif
        container = RyadomSchema.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
