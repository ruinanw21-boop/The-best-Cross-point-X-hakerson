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
                VStack(alignment: .leading, spacing: 22) {
                    cardLanguage(primary, prominent: true)
                    Divider().overlay(CampusStyle.cardInk.opacity(0.12))
                    cardLanguage(primary.other, prominent: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
                .foregroundStyle(CampusStyle.cardInk)
                .background(CampusStyle.paper, in: RoundedRectangle(cornerRadius: 28))
                .padding(18)
            }
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

                    if let recordReply {
                        Button(action: recordReply) {
                            Label(lang.text("Record reply"), systemImage: "plus.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
    }

    private func cardLanguage(_ cardLanguage: CardLanguage, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: cardLanguage.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CampusStyle.cardInk.opacity(0.75))

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
    }
}
