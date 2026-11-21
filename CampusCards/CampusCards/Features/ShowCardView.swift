import SwiftUI

struct CardContent: Identifiable {
    let id = UUID()
    let title: String
    let text: BilingualText
}

struct ShowCardView: View {
    @Environment(\.cardLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var primary: CardLanguage = .chinese
    let card: CardContent
    var recordReply: (() -> Void)?

    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    cardLanguage(primary, prominent: true)
                    cardLanguage(primary.other, prominent: false)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(lang.text(card.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text("Close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        primary = primary.other
                    } label: {
                        Label(lang.text("Swap card languages"), systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let recordReply {
                    Button(action: recordReply) {
                        Label(lang.text("Translate reply"), systemImage: "character.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                }
            }
        }
    }

    private func cardLanguage(_ cardLanguage: CardLanguage, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: cardLanguage.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(prominent ? CampusStyle.translationInk : .secondary)

            if card.text[cardLanguage].isEmpty {
                Text(lang.text("Translation needed")).font(.body)
            } else {
                Text(verbatim: card.text[cardLanguage])
                    .font(prominent ? .largeTitle.weight(.bold) : .title3)
                    .environment(\.locale, cardLanguage.locale)
                    .accessibilityIdentifier(prominent ? "card-primary" : "card-secondary")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(prominent ? CampusStyle.translationSurface : CampusStyle.surface,
                    in: RoundedRectangle(cornerRadius: 24))
    }
}
