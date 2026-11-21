import SwiftData
import SwiftUI

struct PrepareCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.cardLanguage) private var language
    @State private var scenario: TaskScenario = .enrollment
    @State private var fields = TaskScenario.enrollment.defaultFields
    @State private var customTitle = BilingualText()
    @State private var customQuestion = BilingualText()
    @State private var preview: CardContent?
    @State private var isCreating = false
    @State private var saveError = false
    let onCreate: (CampusTask) -> Void

    private var lang: CardLanguage { language.wrappedValue }
    private var title: BilingualText { scenario == .custom ? customTitle.cleaned : scenario.title }
    private var orderedFields: [RequirementKind] { RequirementKind.allCases.filter(fields.contains) }
    private var question: BilingualText {
        scenario == .custom ? customQuestion.cleaned : scenario.question(asking: orderedFields)
    }

    var body: some View {
        CampusPage {
            VStack(alignment: .leading, spacing: 14) {
                templates
                if scenario == .custom {
                    customInput
                }
                requirements
                if !question.isEmpty {
                    previewButton
                }
            }
        }
        .navigationTitle(lang.text("New task"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CampusPrimaryAction(title: lang.text("Create task"), icon: "plus", action: create)
                .disabled(isCreating || title.isEmpty || question.isEmpty)
                .accessibilityIdentifier("create-task")
                .campusActionBar()
        }
        .fullScreenCover(item: $preview) { ShowCardView(card: $0) }
        .modifier(SaveErrorAlert(presented: $saveError))
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Scenario")

            ForEach(TaskScenario.allCases) { template in
                Button {
                    guard scenario != template else { return }
                    scenario = template
                    fields = template.defaultFields
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: template.icon)
                            .frame(width: 24)
                            .foregroundStyle(CampusStyle.translationInk)
                            .accessibilityHidden(true)
                        Text(verbatim: template.title.preferred(lang))
                            .font(.body.weight(scenario == template ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if scenario == template {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CampusStyle.translationInk)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(scenario == template ? CampusStyle.translationSurface : .clear,
                                in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scenario == template ? .isSelected : [])
                .accessibilityIdentifier("template-\(template.rawValue)")
            }
        }
        .campusPanel()
    }

    @ViewBuilder
    private var customInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Task name")
            TextField(lang.text("Task name in English"), text: $customTitle.english)
            Divider()
            TextField(lang.text("Task name in Chinese"), text: $customTitle.chinese)
        }
        .campusPanel()

        VStack(alignment: .leading, spacing: 12) {
            heading("Your question")
            TextField(lang.text("Question in English"), text: $customQuestion.english, axis: .vertical)
                .lineLimit(2...5)
            Divider()
            TextField(lang.text("Question in Chinese"), text: $customQuestion.chinese, axis: .vertical)
                .lineLimit(2...5)
        }
        .campusPanel(highlighted: true)
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("What do you want to ask?")
            ForEach(RequirementKind.allCases) { kind in
                Toggle(isOn: Binding {
                    fields.contains(kind)
                } set: { selected in
                    if selected { fields.insert(kind) } else { fields.remove(kind) }
                }) {
                    Label(lang.text(kind.label), systemImage: kind.icon)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("ask-\(kind.rawValue)")
            }
        }
        .campusPanel()
    }

    private var previewButton: some View {
        Button {
            preview = .init(title: "Card preview", text: question)
        } label: {
            HStack {
                Label(lang.text("Card preview"), systemImage: "text.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(CampusStyle.translationInk)
            .padding(.vertical, 4)
            .campusPanel(highlighted: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preview-card")
    }

    private func heading(_ title: String) -> some View {
        Text(lang.text(title)).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private func create() {
        guard !isCreating, !title.isEmpty, !question.isEmpty else { return }
        isCreating = true
        do {
            onCreate(try TaskStore(context: context).createTask(
                scenario: scenario, title: title, question: question, fields: orderedFields
            ))
        } catch {
            isCreating = false
            saveError = true
        }
    }
}
