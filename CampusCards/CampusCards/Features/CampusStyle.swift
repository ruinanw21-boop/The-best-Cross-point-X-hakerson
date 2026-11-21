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
    static let actionFill = Color(uiColor: rgb(0x245694))
    static let accent = themed(light: 0x245694, dark: 0x9BC6FA)
    static let canvas = themed(light: 0xF5F8FC, dark: 0x111821)
    static let paper = themed(light: 0xFFFFFF, dark: 0x192431)
    static let ticketInk = themed(light: 0x162D4B, dark: 0xE6EFFC)
    static let rule = themed(light: 0xD5DFEC, dark: 0x34465B)
    static let pending = themed(light: 0x78541B, dark: 0xEACB92)
    static let ticketOrder: [RequirementKind] = [.material, .location, .deadline]

    private static func themed(light: UInt32, dark: UInt32) -> Color {
        let lightColor = rgb(light)
        let darkColor = rgb(dark)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: 1
        )
    }
}

struct TicketSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .foregroundStyle(CampusStyle.ticketInk)
            .background(CampusStyle.paper, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(CampusStyle.rule, lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

struct TicketRule: View {
    var body: some View {
        Divider()
            .overlay(CampusStyle.rule)
            .accessibilityHidden(true)
    }
}

struct TicketQuestion: View {
    @Environment(\.cardLanguage) private var language
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 38
    let text: BilingualText
    let primary: CardLanguage
    var forDisplay = false

    var body: some View {
        VStack(alignment: .leading, spacing: forDisplay ? 22 : 14) {
            passage(primary, emphasized: true)
            TicketRule()
            passage(primary.other, emphasized: false)
        }
    }

    private func passage(_ cardLanguage: CardLanguage, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: cardLanguage.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasized ? CampusStyle.accent : Color.secondary)
                .accessibilityAddTraits(.isHeader)
            if text[cardLanguage].isEmpty {
                Text(language.wrappedValue.text("Translation needed"))
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: text[cardLanguage])
                    .font(forDisplay && emphasized ? .system(size: displaySize, weight: .semibold) : emphasized ? .body : .subheadline)
                    .environment(\.locale, cardLanguage.locale)
                    .accessibilityIdentifier(emphasized ? "card-primary" : "card-secondary")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct TicketField: View {
    let kind: RequirementKind
    let text: BilingualText
    var emptyKey = "To ask"
    var pending = true
    var edited = false
    @Environment(\.cardLanguage) private var language

    var body: some View {
        let lang = language.wrappedValue
        VStack(alignment: .leading, spacing: 6) {
            Label(lang.text(kind.label), systemImage: kind.icon)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if text.isEmpty {
                Text(lang.text(emptyKey))
                    .font(.subheadline)
                    .foregroundStyle(pending ? CampusStyle.pending : Color.secondary)
            } else {
                LanguageLines(text: text, primary: lang)
                if edited {
                    Label(lang.text("Edited during review"), systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(CampusStyle.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
