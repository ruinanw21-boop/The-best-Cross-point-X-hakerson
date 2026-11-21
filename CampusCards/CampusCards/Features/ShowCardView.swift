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
    @State private var primary: CardLanguage = .chinese
    let card: CardContent
    var recordReply: (() -> Void)?

    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        NavigationStack {
            ScrollView {
                TicketSurface {
                    TicketQuestion(text: card.text, primary: primary, forDisplay: card.usesLargeType)
                }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        primary = primary.other
                    } label: {
                        Label(lang.text("Swap card languages"), systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityValue(primary.name)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let recordReply {
                    Button(action: recordReply) {
                        Label(lang.text("Record reply"), systemImage: "plus.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CampusStyle.actionFill)
                    .campusActionBar()
                }
            }
        }
    }
}
