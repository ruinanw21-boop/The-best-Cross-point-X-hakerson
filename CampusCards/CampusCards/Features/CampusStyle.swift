import SwiftUI

private struct CardLanguageKey: EnvironmentKey {
    static let defaultValue: Binding<CardLanguage> = .constant(.english)
}

extension EnvironmentValues {
    var cardLanguage: Binding<CardLanguage> {
        get { self[CardLanguageKey.self] }
        set { self[CardLanguageKey.self] = newValue }
    }
}

enum CampusStyle {
    static let ink = Color(.sRGB, red: 0.27, green: 0.25, blue: 0.76)
    static let cardInk = Color(.sRGB, red: 0.12, green: 0.12, blue: 0.27)
    static let paper = Color(.sRGB, red: 0.95, green: 0.94, blue: 1.0)
}

struct LanguageMenu: View {
    @Environment(\.cardLanguage) private var language

    var body: some View {
        Menu {
            Picker("Language", selection: language) {
                ForEach(CardLanguage.allCases) { choice in
                    Text(verbatim: choice.name).tag(choice)
                }
            }
        } label: {
            Label(language.wrappedValue.text("Language"), systemImage: "globe")
        }
        .accessibilityIdentifier("app-language")
    }
}

struct LanguageLines: View {
    let text: BilingualText
    let primary: CardLanguage
    @Environment(\.cardLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !text[primary].isEmpty {
                Text(verbatim: text[primary])
                    .font(.body.weight(.semibold))
                    .environment(\.locale, primary.locale)
            }
            if !text[primary.other].isEmpty {
                Text(verbatim: text[primary.other])
                    .font(text[primary].isEmpty ? .body.weight(.semibold) : .subheadline)
                    .foregroundStyle(text[primary].isEmpty ? .primary : .secondary)
                    .environment(\.locale, primary.other.locale)
            }
            if text.isPartial {
                Label(language.wrappedValue.text("Translation needed"), systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SaveErrorAlert: ViewModifier {
    @Environment(\.cardLanguage) private var language
    @Binding var presented: Bool

    func body(content: Content) -> some View {
        let lang = language.wrappedValue
        content.alert(lang.text("Couldn’t save changes"), isPresented: $presented) {
            Button(lang.text("OK"), role: .cancel) {}
        } message: {
            Text(lang.text("Your changes are still available here. Try saving again."))
        }
    }
}
