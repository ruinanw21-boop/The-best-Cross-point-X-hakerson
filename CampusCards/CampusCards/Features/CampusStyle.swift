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
    static let actionFill = Color(uiColor: rgb(0x2448D8))
    static let accent = themed(light: 0x2448D8, dark: 0xAEBFFF)
    static let canvas = themed(light: 0xF3F5FA, dark: 0x11182B)
    static let paper = themed(light: 0xFFFFFF, dark: 0x1C2540)
    static let ticketInk = themed(light: 0x152143, dark: 0xF1F4FF)
    static let muted = themed(light: 0x526183, dark: 0xB2BED8)
    static let rule = themed(light: 0xDCE3F0, dark: 0x374461)
    static let mist = themed(light: 0xE7EDFF, dark: 0x28365D)
    static let pending = themed(light: 0x78541B, dark: 0xEACB92)
    static let signal = Color(uiColor: rgb(0xE0F48A))
    static let signalInk = Color(uiColor: rgb(0x202D13))
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
    let text: BilingualText
    let primary: CardLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    .font(emphasized ? .body : .subheadline)
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

struct DeskMark: View {
    var body: some View {
        Image(systemName: "bubble.left.and.bubble.right")
            .font(.system(size: 17, weight: .bold))
            .frame(width: 39, height: 39)
            .foregroundStyle(CampusStyle.actionFill)
            .background(CampusStyle.signal, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct DeskRouteGraphic: View {
    var body: some View {
        Canvas { context, size in
            let start = CGPoint(x: size.width * 0.05, y: size.height * 0.78)
            let turn = CGPoint(x: size.width * 0.54, y: size.height * 0.78)
            let destination = CGPoint(x: size.width * 0.87, y: size.height * 0.16)
            var path = Path()
            path.move(to: start)
            path.addLine(to: turn)
            path.addQuadCurve(to: destination, control: CGPoint(x: destination.x, y: turn.y))
            context.stroke(path, with: .color(.white.opacity(0.64)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
            for point in [start, turn, destination] {
                let isDestination = point == destination
                let radius: CGFloat = isDestination ? 6 : 3.5
                let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color(isDestination ? CampusStyle.signal : .white.opacity(0.72)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct DeskHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(verbatim: title)
                .font(.title2.weight(.bold))
                .foregroundStyle(CampusStyle.ticketInk)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(CampusStyle.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeskButtonStyle: ButtonStyle {
    enum Tone { case primary, soft, signal }
    let tone: Tone
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.46)
    }

    private var foreground: Color {
        switch tone {
        case .primary: .white
        case .soft: CampusStyle.accent
        case .signal: CampusStyle.signalInk
        }
    }

    private var background: Color {
        switch tone {
        case .primary: CampusStyle.actionFill
        case .soft: CampusStyle.mist
        case .signal: CampusStyle.signal
        }
    }
}

struct CampusPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView { content().deskPage() }
            .scrollDismissesKeyboard(.interactively)
            .background(CampusStyle.canvas.ignoresSafeArea())
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
                    ProgressView().tint(.white).accessibilityLabel(title)
                } else if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(DeskButtonStyle(tone: .primary))
    }
}

struct CampusLanguagePair: View {
    let first: CardLanguage
    let firstLabel: String
    let secondLabel: String
    let swapLabel: String
    let swapIdentifier: String
    let swap: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            language(first, label: firstLabel)
            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(CampusStyle.accent)
                    .background(CampusStyle.mist, in: Circle())
            }
            .buttonStyle(.plain)
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

extension View {
    func campusPanel(highlighted: Bool = false, inset: CGFloat = 16) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(inset)
            .background(highlighted ? CampusStyle.mist : CampusStyle.paper,
                        in: RoundedRectangle(cornerRadius: 21))
    }

    func deskInput() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(CampusStyle.paper, in: RoundedRectangle(cornerRadius: 16))
    }

    func deskPage() -> some View {
        frame(maxWidth: 580, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
    }

    func campusActionBar() -> some View {
        controlSize(.large)
            .frame(maxWidth: 580)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(CampusStyle.canvas)
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
