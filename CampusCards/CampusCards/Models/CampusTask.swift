import Foundation
import SwiftData

enum CardLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }
    var name: String { self == .english ? "English" : "简体中文" }
    var other: Self { self == .english ? .chinese : .english }

    func text(_ key: String) -> String {
        let bundle = Bundle.main.url(forResource: rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

struct BilingualText: Hashable {
    var english = ""
    var chinese = ""

    subscript(language: CardLanguage) -> String {
        get { language == .english ? english : chinese }
        set {
            switch language {
            case .english: english = newValue
            case .chinese: chinese = newValue
            }
        }
    }

    var cleaned: Self { .init(english: english.cleaned, chinese: chinese.cleaned) }
    var isEmpty: Bool { english.isEmpty && chinese.isEmpty }
    var isPartial: Bool { !isEmpty && (english.isEmpty || chinese.isEmpty) }

    func preferred(_ language: CardLanguage) -> String {
        self[language].isEmpty ? self[language.other] : self[language]
    }
}

extension String {
    var cleaned: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum TaskScenario: String, CaseIterable, Identifiable {
    case enrollment, lostProperty, custom

    var id: Self { self }

    var title: BilingualText {
        switch self {
        case .enrollment: .init(english: "Submit enrollment documents", chinese: "补交入学材料")
        case .lostProperty: .init(english: "Collect lost property", chinese: "领取失物")
        case .custom: .init(english: "Custom task", chinese: "自定义事项")
        }
    }

    var icon: String {
        switch self {
        case .enrollment: "doc.text"
        case .lostProperty: "bag"
        case .custom: "square.and.pencil"
        }
    }

    var defaultFields: Set<RequirementKind> {
        switch self {
        case .enrollment: [.location, .material, .deadline]
        case .lostProperty: [.location, .material]
        case .custom: [.location]
        }
    }

    func question(asking kinds: [RequirementKind]) -> BilingualText {
        let greeting: BilingualText
        switch self {
        case .enrollment:
            greeting = .init(
                english: "Hi, I’m here to submit some additional enrollment documents.",
                chinese: "您好，我来补交入学材料。"
            )
        case .lostProperty:
            greeting = .init(english: "Hi, I’m here to collect a lost item.", chinese: "您好，我来领取失物。")
        case .custom:
            return .init()
        }
        return .init(
            english: ([greeting.english] + kinds.map { $0.question.english }).joined(separator: "\n"),
            chinese: ([greeting.chinese] + kinds.map { $0.question.chinese }).joined(separator: "\n")
        )
    }
}

@Model
final class CampusTask {
    @Attribute(.unique) var id: UUID
    var scenarioCode: String
    var titleEnglish: String
    var titleChinese: String
    var questionEnglish: String
    var questionChinese: String
    var requestedFields: [String]
    var isComplete: Bool
    var createdAt: Date
    var updatedAt: Date

    init(scenario: TaskScenario, title: BilingualText, question: BilingualText, fields: [RequirementKind]) {
        let now = Date()
        id = UUID()
        scenarioCode = scenario.rawValue
        titleEnglish = title.english
        titleChinese = title.chinese
        questionEnglish = question.english
        questionChinese = question.chinese
        requestedFields = fields.map(\.rawValue)
        isComplete = false
        createdAt = now
        updatedAt = now
    }

    var scenario: TaskScenario { TaskScenario(rawValue: scenarioCode) ?? .custom }
    var title: BilingualText { .init(english: titleEnglish, chinese: titleChinese) }
    var question: BilingualText { .init(english: questionEnglish, chinese: questionChinese) }
    var fields: [RequirementKind] { requestedFields.compactMap(RequirementKind.init(rawValue:)) }
}
