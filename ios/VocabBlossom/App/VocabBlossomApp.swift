import SwiftData
import SwiftUI

@main
struct VocabBlossomApp: App {
    @State private var settings = AppSettings()

    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WordProgress.self, AnswerLog.self)
        } catch {
            fatalError("学習データの保存領域を開けませんでした: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
