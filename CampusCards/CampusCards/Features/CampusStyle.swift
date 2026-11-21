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
    static let ink = Color(.sRGB, red: 0.27, green: 0.25, blue: 0.76)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let translationSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.13, blue: 0.25, alpha: 1)
            : UIColor(red: 0.91, green: 0.90, blue: 0.99, alpha: 1)
    })
    static let translationInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.76, green: 0.73, blue: 1.0, alpha: 1)
            : UIColor(red: 0.27, green: 0.25, blue: 0.76, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let pageWidth: CGFloat = 560
}


struct CampusPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: CampusStyle.pageWidth)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CampusStyle.background)
    }
}

extension View {
    func campusPanel(highlighted: Bool = false, inset: CGFloat = 16) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(inset)
            .background(highlighted ? CampusStyle.translationSurface : CampusStyle.surface,
                        in: RoundedRectangle(cornerRadius: 24))
    }

    func campusActionBar() -> some View {
        frame(maxWidth: CampusStyle.pageWidth)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }
}

struct CampusPrimaryAction: View {
    let title: String
    var icon: String? = nil
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().accessibilityLabel(title)
                } else if let icon {
                    Label(title, systemImage: icon).font(.headline)
                } else {
                    Text(title).font(.headline)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

struct CampusLanguagePair: View {
    let first: CardLanguage
    let firstLabel: String
    let secondLabel: String
    let swapLabel: String
    let swapIdentifier: String
    let swap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            language(first, label: firstLabel)
            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(CampusStyle.translationSurface, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(CampusStyle.translationInk)
            .accessibilityLabel(swapLabel)
            .accessibilityIdentifier(swapIdentifier)
            language(first.other, label: secondLabel)
        }
        .campusPanel(inset: 10)
    }

    private func language(_ choice: CardLanguage, label: String) -> some View {
        Text(verbatim: choice.name)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
            .accessibilityValue(choice.name)
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
