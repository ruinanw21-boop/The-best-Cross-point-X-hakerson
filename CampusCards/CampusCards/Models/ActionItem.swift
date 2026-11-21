import Foundation
import SwiftData

enum RequirementKind: String, Codable, CaseIterable, Identifiable {
    case location, material, deadline

    var id: Self { self }
    var label: String {
        switch self {
        case .location: "Location"
        case .material: "Bring"
        case .deadline: "Time"
        }
    }

    var icon: String {
        switch self {
        case .location: "mappin"
        case .material: "checkmark.circle"
        case .deadline: "clock"
        }
    }

    var question: BilingualText {
        switch self {
        case .location: .init(english: "Which desk should I go to?", chinese: "请问我应该去哪个柜台？")
        case .material: .init(english: "What do I need to bring?", chinese: "我需要带什么？")
        case .deadline: .init(english: "What time should I come by?", chinese: "请问我最晚几点到？")
        }
    }
}

struct ConfirmedTime: Codable, Equatable {
    var weekday: Weekday = .unspecified
    var minuteOfDay = 16 * 60
    var isCutoff = true

    var text: BilingualText {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let meridiem = hour < 12 ? "a.m." : "p.m."
        let englishClock = "\(hour12):\(String(format: "%02d", minute)) \(meridiem)"
        let englishDay = weekday == .unspecified ? "" : " on \(weekday.english)"
        let period: String
        switch hour {
        case 0..<6: period = "凌晨"
        case 6..<12: period = "上午"
        case 12: period = "中午"
        default: period = "下午"
        }
        let chineseHours = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"]
        let chineseHour = chineseHours[hour == 0 ? 0 : hour12]
        let chineseMinute = minute == 0 ? "" : (minute == 30 ? "半" : "\(minute)分")
        return .init(
            english: "\(isCutoff ? "By" : "At") \(englishClock)\(englishDay)",
            chinese: "\(weekday.chinese)\(period)\(chineseHour)点\(chineseMinute)\(isCutoff ? "前" : "")"
        )
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case unspecified, monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Self { self }
    var english: String {
        ["No weekday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][rawValue]
    }
    var chinese: String {
        ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"][rawValue]
    }
}

@Model
final class ActionItem {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var sourceTurnID: UUID
    var kindCode: String
    var valueEnglish: String
    var valueChinese: String
    var timeWeekday: Int?
    var timeMinute: Int?
    var timeIsCutoff: Bool
    var wasEditedDuringReview: Bool? = nil
    var isChecked: Bool
    var createdAt: Date

    init(taskID: UUID, sourceTurnID: UUID, field: FieldDraft, createdAt: Date) {
        id = UUID()
        self.taskID = taskID
        self.sourceTurnID = sourceTurnID
        kindCode = field.kind.rawValue
        valueEnglish = field.confirmedText.english
        valueChinese = field.confirmedText.chinese
        timeWeekday = field.confirmedTime?.weekday.rawValue
        timeMinute = field.confirmedTime?.minuteOfDay
        timeIsCutoff = field.confirmedTime?.isCutoff ?? true
        wasEditedDuringReview = field.wasEditedDuringReview
        isChecked = false
        self.createdAt = createdAt
    }

    var kind: RequirementKind { RequirementKind(rawValue: kindCode) ?? .location }

    var time: ConfirmedTime? {
        guard let timeMinute, (0..<1440).contains(timeMinute) else { return nil }
        return .init(
            weekday: Weekday(rawValue: timeWeekday ?? 0) ?? .unspecified,
            minuteOfDay: timeMinute,
            isCutoff: timeIsCutoff
        )
    }

    var text: BilingualText { time?.text ?? .init(english: valueEnglish, chinese: valueChinese) }

    func revise(from field: FieldDraft, sourceTurnID: UUID) {
        let previousText = text
        let previousTime = time
        self.sourceTurnID = sourceTurnID
        valueEnglish = field.confirmedText.english
        valueChinese = field.confirmedText.chinese
        timeWeekday = field.confirmedTime?.weekday.rawValue
        timeMinute = field.confirmedTime?.minuteOfDay
        timeIsCutoff = field.confirmedTime?.isCutoff ?? true
        wasEditedDuringReview = field.wasEditedDuringReview
        if previousText != text || previousTime != time {
            isChecked = false
        }
    }
}
