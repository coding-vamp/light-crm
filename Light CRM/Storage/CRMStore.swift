import Foundation
import SwiftData
import Observation

@MainActor @Observable final class CRMStore {
    let container: ModelContainer
    let context: ModelContext
    let root: URL
    let vault: FileVault
    private(set) var records: [CRMRecord] = []
    private(set) var currency = "USD"
    var busy = false
    var errorMessage: String?
    var notice: String?
    private var settings: CRMSettings

    nonisolated static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LightCRM", isDirectory: true)
    }

    init(root: URL = CRMStore.defaultRoot, inMemory: Bool = false) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema([CRMRecord.self, Attachment.self, CRMSettings.self])
        let config = inMemory ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(schema: schema, url: root.appendingPathComponent("CRM.store"), cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container); context.autosaveEnabled = false
        vault = FileVault(root: root.appendingPathComponent("Attachments", isDirectory: true))
        if let saved = try context.fetch(FetchDescriptor<CRMSettings>()).first { settings = saved }
        else {
            settings = CRMSettings(currency: Locale.current.currency?.identifier ?? "USD")
            context.insert(settings); try context.save()
        }
        currency = settings.currency
        try reload()
    }

    func reload() throws { records = try context.fetch(FetchDescriptor<CRMRecord>(sortBy: [SortDescriptor(\.createdAt)])) }
    func record(_ id: UUID?) -> CRMRecord? { records.first { $0.id == id } }
    func all(_ kind: RecordKind) -> [CRMRecord] { records.filter { $0.kind == kind }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    var isEmpty: Bool { records.isEmpty }
    func money(_ value: Decimal) -> String { Money.display(value, currency: currency) }
    func report(_ error: Error) { errorMessage = error.localizedDescription }

    private func commit() throws {
        do { try context.save(); try reload() }
        catch { context.rollback(); try? reload(); throw error }
    }

    func setCurrency(_ code: String) throws {
        guard Locale.commonISOCurrencyCodes.contains(code) else { throw CRMError.invalid("Choose a supported ISO currency code.") }
        settings.currency = code
        try commit(); currency = code
    }

    func snapshot() -> Snapshot {
        Snapshot(records: records.map(RecordData.init), attachments: records.flatMap(\.attachments).map(AttachmentData.init), currency: currency)
    }

    @discardableResult func save(_ draft: RecordData) throws -> CRMRecord {
        var data = draft
        data.name = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
        data.lastName = data.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        var proposed = snapshot()
        proposed.records.removeAll { $0.id == data.id }; proposed.records.append(data)
        try FileVault.validateRecords(proposed)
        let r = record(data.id) ?? CRMRecord(kind: data.kind, name: data.name, id: data.id)
        if r.modelContext == nil { context.insert(r) }
        apply(data, to: r)
        r.updatedAt = .now
        r.company = record(data.companyID); r.contact = record(data.contactID); r.deal = record(data.dealID)
        try commit()
        return r
    }

    private func apply(_ d: RecordData, to r: CRMRecord) {
        r.name = d.name; r.lastName = d.lastName; r.email = d.email; r.phone = d.phone; r.website = d.website
        r.notes = d.notes; r.amount = d.amount; r.stageRaw = d.stage.rawValue; r.serviceRaw = d.service.rawValue
        r.nextAction = d.nextAction; r.due = d.due; r.launch = d.launch; r.completed = d.completed
        r.createdAt = d.createdAt; r.updatedAt = d.updatedAt
    }

    func move(_ r: CRMRecord, to stage: DealStage) {
        guard !busy, r.kind == .deal else { return }
        r.stageRaw = stage.rawValue; r.updatedAt = .now
        do { try commit() } catch { report(error) }
    }
    func toggle(_ r: CRMRecord) {
        guard !busy, r.kind == .task else { return }
        r.completed.toggle(); r.updatedAt = .now
        do { try commit() } catch { report(error) }
    }

    func deletionExplanation(_ record: CRMRecord) -> String {
        let linked = records.filter { $0.company?.id == record.id || $0.contact?.id == record.id || $0.deal?.id == record.id }
        return "Delete “\(record.title)”? \(linked.count) linked record(s) will be kept and unlinked. \(record.attachments.count) owned document(s) will have their managed copies removed. Your original imported files will not be changed. This cannot be undone."
    }

    func delete(_ r: CRMRecord) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let paths = r.attachments.map(\.relativePath)
        do {
            // Explicit unlinking makes behavior deterministic even without inverse self relationships.
            for other in records {
                if other.company?.id == r.id { other.company = nil }
                if other.contact?.id == r.id { other.contact = nil }
                if other.deal?.id == r.id { other.deal = nil }
            }
            context.delete(r); try commit()
            try await vault.remove(paths)
        } catch { report(error) }
    }

    func importFiles(_ urls: [URL], owner: CRMRecord) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var failures: [String] = []
        var imported = 0
        for url in urls {
            do {
                let data = try await vault.importFile(url, ownerID: owner.id)
                let attachment = Attachment(data, owner: owner); context.insert(attachment)
                do { try commit(); imported += 1 }
                catch { try? await vault.remove([data.relativePath]); throw error }
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { errorMessage = "Imported \(imported) document(s).\n\n" + failures.joined(separator: "\n") }
    }

    func deleteAttachment(_ attachment: Attachment) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let path = attachment.relativePath
        do { context.delete(attachment); try commit(); try await vault.remove([path]) }
        catch { report(error) }
    }

    func export(to destination: URL) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await vault.export(snapshot(), to: destination); notice = "Backup saved to \(destination.lastPathComponent)." }
        catch { report(error) }
    }

    func restore(from package: URL) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let safety = try await replaceFromBackup(package)
            notice = "Restore completed. A safety backup of your previous data is in \(safety.path)."
        } catch { report(error) }
    }

    /// Exposed internally for deterministic failure tests. No database changes occur
    /// until validation, safety export, and staging all succeed.
    func replaceFromBackup(_ package: URL, beforeCommit: (() throws -> Void)? = nil) async throws -> URL {
        _ = try await vault.validate(package)
        let backups = root.appendingPathComponent("Safety Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let safety = backups.appendingPathComponent("Before-restore-\(UUID().uuidString).lightcrmbackup")
        let previous = snapshot()
        try await vault.export(previous, to: safety)
        let staged = try await vault.stage(package)
        do {
            // Reuse matching stable identifiers to avoid unique-key delete/insert conflicts.
            let incomingIDs = Set(staged.records.map(\.id))
            for r in records { r.company = nil; r.contact = nil; r.deal = nil }
            for a in try context.fetch(FetchDescriptor<Attachment>()) { context.delete(a) }
            for r in records where !incomingIDs.contains(r.id) { context.delete(r) }
            var map: [UUID: CRMRecord] = [:]
            for data in staged.records {
                let r = record(data.id) ?? CRMRecord(kind: data.kind, name: data.name, id: data.id)
                if r.modelContext == nil { context.insert(r) }
                r.kindRaw = data.kind.rawValue; apply(data, to: r); map[data.id] = r
            }
            for d in staged.records {
                map[d.id]?.company = d.companyID.flatMap { map[$0] }
                map[d.id]?.contact = d.contactID.flatMap { map[$0] }
                map[d.id]?.deal = d.dealID.flatMap { map[$0] }
            }
            for a in staged.attachments {
                guard let owner = map[a.ownerID] else { throw CRMError.invalid("Missing attachment owner.") }
                context.insert(Attachment(a, owner: owner))
            }
            settings.currency = staged.currency
            try beforeCommit?()
            try commit(); currency = staged.currency
        } catch {
            context.rollback(); try? reload()
            try? await vault.remove(staged.attachments.map(\.relativePath))
            throw error
        }
        // Old files are no longer referenced. Cleanup failures must never undo a committed restore.
        do { try await vault.remove(previous.attachments.map(\.relativePath)) }
        catch { report(error) }
        return safety
    }

    func loadSamples() throws {
        guard isEmpty else { throw CRMError.invalid("Sample data is only available in an empty workspace.") }
        let studio = CRMRecord(kind: .company, name: "Juniper Studio")
        studio.website = "https://example.com"; studio.notes = "Fictional architecture studio. Warm, editorial portfolio with room to grow."
        let bakery = CRMRecord(kind: .company, name: "Sunday Bread")
        let contact = CRMRecord(kind: .contact, name: "Alex"); contact.lastName = "Rivera"
        contact.email = "alex@example.com"; contact.company = studio
        let projects: [(String, String, DealStage, CRMRecord)] = [
            ("A new home for Juniper", "8500", .proposal, studio),
            ("Preorders, made simple", "4200", .discovery, bakery),
            ("Spring campaign", "2600", .newInquiry, studio),
            ("Care & maintenance", "1200", .won, bakery)]
        [studio, bakery, contact].forEach { context.insert($0) }
        for (index, item) in projects.enumerated() {
            let deal = CRMRecord(kind: .deal, name: item.0); deal.amount = item.1; deal.stageRaw = item.2.rawValue
            deal.company = item.3; deal.contact = item.3 == studio ? contact : nil
            deal.nextAction = index == 0 ? "Follow up on the proposal" : "Schedule a discovery call"
            deal.due = Day(Calendar.current.date(byAdding: .day, value: index, to: .now)!)
            deal.notes = "Sample project. Replace this with your own brief, scope, and decisions."
            context.insert(deal)
            let task = CRMRecord(kind: .task, name: index == 0 ? "Send the revised proposal" : "Prepare \(item.3.name) project notes")
            task.deal = deal; task.contact = deal.contact
            task.due = index == 2 ? nil : Day(Calendar.current.date(byAdding: .day, value: index - 1, to: .now)!)
            task.completed = index == 3; context.insert(task)
        }
        try commit()
    }
}
