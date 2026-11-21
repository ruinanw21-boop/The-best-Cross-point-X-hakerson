import SwiftUI

struct CardContent: Identifiable {
    let id = UUID()
    let title: String
    let text: BilingualText
    var usesLargeType = true
}

struct ShowCardView: View {
    @Environment(\.cardLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 38
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    primaryPanel
                    secondaryPanel
                }
                .background(CampusStyle.paper)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .deskPage()
            }
            .background(CampusStyle.canvas.ignoresSafeArea())
            .navigationTitle(lang.text(card.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(lang.text("Close")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { primary = primary.other } label: {
                        Label(lang.text("Swap card languages"), systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityValue(primary.name)
                    .accessibilityIdentifier("swap-card-languages")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let recordReply {
                    Button(action: recordReply) {
                        Label(lang.text("Record reply"), systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DeskButtonStyle(tone: .primary))
                    .accessibilityIdentifier("translate-card-reply")
                    .campusActionBar()
                }
            }
        }
    }

    private var primaryPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Text(verbatim: primary.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CampusStyle.signal)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                DeskMark()
            }
            passage(primary)
                .font(card.usesLargeType ? .system(size: displaySize, weight: .semibold) : .title2.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("card-primary")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusStyle.actionFill)
    }

    private var secondaryPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(verbatim: primary.other.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CampusStyle.accent)
                .accessibilityAddTraits(.isHeader)
            passage(primary.other)
                .font(.body)
                .foregroundStyle(CampusStyle.ticketInk)
                .accessibilityIdentifier("card-secondary")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func passage(_ cardLanguage: CardLanguage) -> some View {
        Text(verbatim: card.text[cardLanguage].isEmpty ? lang.text("Translation needed") : card.text[cardLanguage])
            .environment(\.locale, card.text[cardLanguage].isEmpty ? lang.locale : cardLanguage.locale)
            .fixedSize(horizontal: false, vertical: true)
    }
}
