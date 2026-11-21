import SwiftUI
import UIKit

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
    private static let serviceBlue = UIColor(red: 36.0 / 255, green: 86.0 / 255, blue: 148.0 / 255, alpha: 1)
    static let actionFill = Color(uiColor: serviceBlue)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 155.0 / 255, green: 198.0 / 255, blue: 250.0 / 255, alpha: 1)
            : serviceBlue
    })
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let paper = Color(uiColor: .secondarySystemGroupedBackground)
}

extension View {
    func campusActionBar() -> some View {
        controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.regularMaterial)
    }
}

struct LanguageMenu: View {
    @Environment(\.cardLanguage) private var language

    var body: some View {
        Menu {
            Picker(language.wrappedValue.text("Language"), selection: language) {
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
