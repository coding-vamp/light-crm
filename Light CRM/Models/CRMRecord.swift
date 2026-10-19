import Foundation
import SwiftData

nonisolated enum RecordKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case contact, company, deal, task
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var plural: String { self == .company ? "Companies" : title + "s" }
    var symbol: String {
        switch self { case .contact: "person.2"; case .company: "building.2"; case .deal: "rectangle.3.group"; case .task: "checkmark.circle" }
    }
}

nonisolated enum DealStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case newInquiry = "New inquiry", discovery = "Discovery", proposal = "Proposal sent"
    case awaiting = "Awaiting commitment", won = "Won", lost = "Lost"
    var id: String { rawValue }
    var isActive: Bool { self != .won && self != .lost }
}

nonisolated enum Service: String, Codable, CaseIterable, Identifiable, Sendable {
    case website = "New website", redesign = "Redesign", landing = "Landing page"
    case commerce = "E-commerce", maintenance = "Maintenance", other = "Other"
    var id: String { rawValue }
}

/// A Gregorian civil day, independent of time zone and daylight-saving transitions.
nonisolated struct Day: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    init(_ date: Date = .now) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        year = c.year!; month = c.month!; day = c.day!
    }
    var date: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }
    var isValid: Bool { (1...9999).contains(year) && Day(date) == self }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
    var label: String { date.formatted(date: .abbreviated, time: .omitted) }
}

nonisolated enum Money {
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let escaped = NSRegularExpression.escapedPattern(for: separator)
        guard trimmed.range(of: "^[0-9]+(?:\(escaped)[0-9]{1,3})?$", options: .regularExpression) != nil,
              let number = Decimal(string: trimmed.replacingOccurrences(of: separator, with: "."), locale: Locale(identifier: "en_US_POSIX")),
              number >= 0, number <= Decimal(999_999_999_999) else { return nil }
        return number
    }
    static func canonical(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    static func display(_ value: Decimal, currency: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value) \(currency)"
    }
    static func editable(_ value: Decimal) -> String {
        canonical(value).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
}

/// A small typed graph keeps shared editing and backup rules in one place. The service
/// validates allowed relationship kinds; delete rules never cascade to client work.
@Model final class CRMRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var name: String
    var lastName: String
    var email: String
    var phone: String
    var website: String
    var notes: String
    var amount: String
    var stageRaw: String
    var serviceRaw: String
    var nextAction: String
    var due: Day?
    var launch: Day?
    var completed: Bool
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .nullify) var company: CRMRecord?
    @Relationship(deleteRule: .nullify) var contact: CRMRecord?
    @Relationship(deleteRule: .nullify) var deal: CRMRecord?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.owner) var attachments: [Attachment] = []

    init(kind: RecordKind, name: String, id: UUID = UUID()) {
        self.id = id; kindRaw = kind.rawValue; self.name = name; lastName = ""
        email = ""; phone = ""; website = ""; notes = ""; amount = "0"
        stageRaw = DealStage.newInquiry.rawValue; serviceRaw = Service.website.rawValue
        nextAction = ""; completed = false; createdAt = .now; updatedAt = .now
    }
    var kind: RecordKind { RecordKind(rawValue: kindRaw) ?? .contact }
    var title: String { [name, kind == .contact ? lastName : ""].filter { !$0.isEmpty }.joined(separator: " ") }
    var stage: DealStage { DealStage(rawValue: stageRaw) ?? .newInquiry }
    var value: Decimal { Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    var client: String { company?.title ?? contact?.title ?? "No client linked" }
    var isOverdue: Bool { due.map { $0 < Day() } == true && (kind == .task ? !completed : stage.isActive) }
}

@Model final class Attachment {
    @Attribute(.unique) var id: UUID
    var filename: String
    var relativePath: String
    var size: Int64
    var type: String
    var addedAt: Date
    var owner: CRMRecord?
    init(_ data: AttachmentData, owner: CRMRecord) {
        id = data.id; filename = data.filename; relativePath = data.relativePath
        size = data.size; type = data.type; addedAt = data.addedAt; self.owner = owner
    }
}

@Model final class CRMSettings {
    @Attribute(.unique) var key: String = "settings"
    var currency: String
    init(currency: String) { self.currency = currency }
}

nonisolated struct RecordData: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: RecordKind
    var name = ""
    var lastName = ""
    var email = ""
    var phone = ""
    var website = ""
    var notes = ""
    var amount = "0"
    var stage: DealStage = .newInquiry
    var service: Service = .website
    var nextAction = ""
    var due: Day?
    var launch: Day?
    var completed = false
    var createdAt = Date.now
    var updatedAt = Date.now
    var companyID: UUID?
    var contactID: UUID?
    var dealID: UUID?
}

nonisolated struct AttachmentData: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var ownerID: UUID
    var filename: String
    var relativePath: String
    var size: Int64
    var type: String
    var addedAt: Date
    var sha256: String?
}

nonisolated struct Snapshot: Codable, Sendable {
    var records: [RecordData]
    var attachments: [AttachmentData]
    var currency: String
}

extension RecordData {
    @MainActor init(_ r: CRMRecord) {
        id = r.id; kind = r.kind; name = r.name; lastName = r.lastName; email = r.email; phone = r.phone
        website = r.website; notes = r.notes; amount = r.amount; stage = r.stage
        service = Service(rawValue: r.serviceRaw) ?? .other; nextAction = r.nextAction
        due = r.due; launch = r.launch; completed = r.completed; createdAt = r.createdAt; updatedAt = r.updatedAt
        companyID = r.company?.id; contactID = r.contact?.id; dealID = r.deal?.id
    }
}
extension AttachmentData {
    @MainActor init(_ a: Attachment) {
        id = a.id; ownerID = a.owner!.id; filename = a.filename; relativePath = a.relativePath
        size = a.size; type = a.type; addedAt = a.addedAt
    }
}

nonisolated enum CRMError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
