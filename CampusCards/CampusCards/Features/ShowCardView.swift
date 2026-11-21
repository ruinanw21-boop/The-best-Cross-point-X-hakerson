import SwiftUI

struct CardContent: Identifiable {
    let id = UUID()
    let title: String
    let text: BilingualText
}

struct ShowCardView: View {
    @Environment(\.cardLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 38
    @State private var primary: CardLanguage = .chinese
    let card: CardContent
    var recordReply: (() -> Void)?

    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    cardLanguage(primary, prominent: true)
                    Divider()
                    cardLanguage(primary.other, prominent: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(CampusStyle.paper, in: RoundedRectangle(cornerRadius: 20))
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .background(CampusStyle.canvas.ignoresSafeArea())
            .navigationTitle(lang.text(card.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text("Close")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        primary = primary.other
                    } label: {
                        Label(lang.text("Swap card languages"), systemImage: "arrow.up.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityValue(primary.name)

                    if let recordReply {
                        Button(action: recordReply) {
                            Label(lang.text("Record reply"), systemImage: "plus.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CampusStyle.actionFill)
                    }
                }
                .campusActionBar()
            }
        }
    }

    private func cardLanguage(_ cardLanguage: CardLanguage, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: cardLanguage.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? CampusStyle.accent : Color.secondary)
                .accessibilityAddTraits(.isHeader)

            if card.text[cardLanguage].isEmpty {
                Text(lang.text("Translation needed"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: card.text[cardLanguage])
                    .font(prominent ? .system(size: displaySize, weight: .semibold) : .title3)
                    .environment(\.locale, cardLanguage.locale)
                    .accessibilityIdentifier(prominent ? "card-primary" : "card-secondary")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
