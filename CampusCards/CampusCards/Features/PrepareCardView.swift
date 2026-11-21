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
    let onCreate: (CampusTask) -> Void

    private var lang: CardLanguage { language.wrappedValue }
    private var title: BilingualText { scenario == .custom ? customTitle.cleaned : scenario.title }
    private var orderedFields: [RequirementKind] { RequirementKind.allCases.filter(fields.contains) }
    private var question: BilingualText {
        scenario == .custom ? customQuestion.cleaned : scenario.question(asking: orderedFields)
    }

    var body: some View {
        Form {
            Section(lang.text("Scenario")) {
                Picker(lang.text("Scenario"), selection: $scenario) {
                    ForEach(TaskScenario.allCases) { template in
                        Text(verbatim: template.title.preferred(lang)).tag(template)
                    }
                }
                .onChange(of: scenario) { _, newValue in
                    fields = newValue.defaultFields
                }
            }

            if scenario == .custom {
                Section(lang.text("Task name")) {
                    TextField(lang.text("Task name in English"), text: $customTitle.english)
                    TextField(lang.text("Task name in Chinese"), text: $customTitle.chinese)
                }
                Section(lang.text("Your question")) {
                    TextField(lang.text("Question in English"), text: $customQuestion.english, axis: .vertical)
                        .lineLimit(2...5)
                    TextField(lang.text("Question in Chinese"), text: $customQuestion.chinese, axis: .vertical)
                        .lineLimit(2...5)
                }
            }

            Section(lang.text("What do you want to ask?")) {
                ForEach(RequirementKind.allCases) { kind in
                    Toggle(lang.text(kind.label), isOn: Binding {
                        fields.contains(kind)
                    } set: { selected in
                        if selected { fields.insert(kind) } else { fields.remove(kind) }
                    })
                }
            }

            if !question.isEmpty {
                Section(lang.text("Card preview")) {
                    LanguageLines(text: question, primary: .chinese)
                        .padding(.vertical, 5)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(lang.text("New task"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
        .safeAreaInset(edge: .bottom) {
            Button(action: create) {
                Text(lang.text("Create task"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(title.isEmpty || question.isEmpty)
            .accessibilityIdentifier("create-task")
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .modifier(SaveErrorAlert(presented: $saveError))
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
