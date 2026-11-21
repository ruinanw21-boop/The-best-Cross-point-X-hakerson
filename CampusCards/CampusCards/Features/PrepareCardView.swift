import SwiftData
import SwiftUI

struct PrepareCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.cardLanguage) private var language
    @State private var scenario: TaskScenario = .enrollment
    @State private var fields = TaskScenario.enrollment.defaultFields
    @State private var customTitle = BilingualText()
    @State private var customQuestion = BilingualText()
    @State private var saveError = false
    @State private var presentedCard: CardContent?
    let onCreate: (CampusTask) -> Void

    private var lang: CardLanguage { language.wrappedValue }
    private var title: BilingualText { scenario == .custom ? customTitle.cleaned : scenario.title }
    private var orderedFields: [RequirementKind] { RequirementKind.allCases.filter(fields.contains) }
    private var question: BilingualText {
        scenario == .custom ? customQuestion.cleaned : scenario.question(asking: orderedFields)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                DeskHeading(title: lang.text("Prepare a question"), subtitle: lang.text("Start with what you need to do."))
                scenarioPicker
                if scenario == .custom { customFields }
                questions
                if !question.isEmpty { preview }
            }
            .deskPage()
        }
        .background(CampusStyle.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(lang.text("New task"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
        .safeAreaInset(edge: .bottom) {
            Button(action: create) {
                Label(lang.text("Create task"), systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DeskButtonStyle(tone: .primary))
            .disabled(title.isEmpty || question.isEmpty)
            .accessibilityIdentifier("create-task")
            .campusActionBar()
        }
        .sheet(item: $presentedCard) { card in
            ShowCardView(card: card)
        }
        .modifier(SaveErrorAlert(presented: $saveError))
    }

    private var scenarioPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            DeskHeading(title: lang.text("Scenario"))
                .padding(.bottom, 4)
            ForEach(TaskScenario.allCases) { choice in
                Button {
                    if scenario != choice {
                        scenario = choice
                        fields = choice.defaultFields
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: choice.icon)
                            .frame(width: 36, height: 36)
                            .foregroundStyle(CampusStyle.accent)
                            .background(CampusStyle.mist, in: RoundedRectangle(cornerRadius: 11))
                            .accessibilityHidden(true)
                        Text(verbatim: choice.title.preferred(lang))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CampusStyle.ticketInk)
                        Spacer(minLength: 8)
                        Image(systemName: scenario == choice ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(scenario == choice ? CampusStyle.accent : CampusStyle.muted)
                            .accessibilityHidden(true)
                    }
                    .padding(10)
                    .frame(minHeight: 52)
                    .background(scenario == choice ? CampusStyle.paper : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scenario == choice ? .isSelected : [])
            }
        }
    }

    private var customFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeskHeading(title: lang.text("Your question"))
            TextField(lang.text("Task name in English"), text: $customTitle.english).deskInput()
            TextField(lang.text("Task name in Chinese"), text: $customTitle.chinese).deskInput()
            TextField(lang.text("Question in English"), text: $customQuestion.english, axis: .vertical)
                .lineLimit(2...5).deskInput()
            TextField(lang.text("Question in Chinese"), text: $customQuestion.chinese, axis: .vertical)
                .lineLimit(2...5).deskInput()
        }
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 6) {
            DeskHeading(title: lang.text("What do you want to ask?"))
                .padding(.bottom, 4)
            ForEach(RequirementKind.allCases) { kind in
                Toggle(isOn: Binding {
                    fields.contains(kind)
                } set: { selected in
                    if selected { fields.insert(kind) } else { fields.remove(kind) }
                }) {
                    Label(lang.text(kind.label), systemImage: kind.icon)
                        .foregroundStyle(CampusStyle.ticketInk)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeskHeading(title: lang.text("Card preview"))
            TicketSurface { TicketQuestion(text: question, primary: lang) }
            Button {
                presentedCard = .init(title: "Card preview", text: question)
            } label: {
                Label(lang.text("Card preview"), systemImage: "arrow.up.right")
            }
            .buttonStyle(DeskButtonStyle(tone: .soft))
            Text(lang.text("Chinese appears first when you show this card."))
                .font(.footnote)
                .foregroundStyle(CampusStyle.muted)
        }
    }

    private func create() {
        do {
            onCreate(try TaskStore(context: context).createTask(
                scenario: scenario, title: title, question: question, fields: orderedFields
            ))
        } catch {
            saveError = true
        }
    }
}
