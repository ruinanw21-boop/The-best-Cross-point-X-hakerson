import SwiftUI

struct CardContent: Identifiable {
    let id = UUID()
    let title: String
    let text: BilingualText
}

struct ShowCardView: View {
    @Environment(\.cardLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var primary: CardLanguage
    let card: CardContent
    let recordReply: (() -> Void)?

    init(card: CardContent, recordReply: (() -> Void)? = nil) {
        self.card = card
        self.recordReply = recordReply
        _primary = State(initialValue: card.text.chinese.isEmpty ? .english : .chinese)
    }

    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        NavigationStack {
            CampusPage {
                VStack(alignment: .leading, spacing: 14) {
                    CampusLanguagePair(
                        first: primary, firstLabel: lang.text("First language"),
                        secondLabel: lang.text("Second language"), swapLabel: lang.text("Swap card languages"),
                        swapIdentifier: "swap-card-languages"
                    ) {
                        primary = primary.other
                    }
                    cardLanguage(primary, prominent: true)
                    cardLanguage(primary.other, prominent: false)
                }
            }
            .navigationTitle(lang.text(card.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text("Close")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let recordReply {
                    CampusPrimaryAction(title: lang.text("Translate reply"), icon: "character.bubble", action: recordReply)
                        .accessibilityIdentifier("translate-card-reply")
                        .campusActionBar()
                }
            }
        }
    }

    private func cardLanguage(_ cardLanguage: CardLanguage, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: cardLanguage.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? CampusStyle.translationInk : .secondary)
                .accessibilityAddTraits(.isHeader)

            if card.text[cardLanguage].isEmpty {
                Text(lang.text("Translation needed")).foregroundStyle(.secondary)
            } else {
                Text(verbatim: card.text[cardLanguage])
                    .font(prominent ? .largeTitle.weight(.semibold) : .title2)
                    .environment(\.locale, cardLanguage.locale)
                    .accessibilityIdentifier(prominent ? "card-primary" : "card-secondary")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .campusPanel(highlighted: prominent, inset: 20)
    }
}
