import SwiftData
import SwiftUI

@main
struct CampusCardsApp: App {
    @AppStorage("appLanguage") private var languageCode = CardLanguage.english.rawValue
    @State private var container: ModelContainer?
    @State private var attemptedLoad = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    TaskListView()
                        .modelContainer(container)
                } else if attemptedLoad {
                    StorageRecoveryView(retry: loadStore)
                } else {
                    ProgressView().task { loadStore() }
                }
            }
            .tint(CampusStyle.ink)
            .environment(\.cardLanguage, language)
            .environment(\.locale, language.wrappedValue.locale)
        }
    }

    private var language: Binding<CardLanguage> {
        Binding {
            CardLanguage(rawValue: languageCode) ?? .english
        } set: {
            languageCode = $0.rawValue
        }
    }

    private func loadStore() {
        defer { attemptedLoad = true }
        guard let store = try? ModelContainer(for: CampusTask.self, ConversationTurn.self, ActionItem.self) else {
            return
        }
        store.mainContext.autosaveEnabled = false
        container = store
    }
}

private struct StorageRecoveryView: View {
    @Environment(\.cardLanguage) private var language
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(language.wrappedValue.text("Couldn’t open your tasks"), systemImage: "tray")
        } actions: {
            Button(language.wrappedValue.text("Try again"), action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
