import XCTest
import SwiftData
import CryptoKit
@testable import LightCRMCore

@MainActor final class CRMTests: XCTestCase {
    private var directories: [URL] = []
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LightCRMTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url); return url
    }
    override func tearDown() async throws {
        for url in directories { try? FileManager.default.removeItem(at: url) }
        directories = []
    }
    private func store() throws -> CRMStore { try CRMStore(root: temporary()) }
    private func sampleFile(_ directory: URL, name: String = "proposal.txt") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("A fictional proposal.\n".utf8).write(to: url)
        return url
    }
    func testMoneyAndCivilDays() throws {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(Money.parse("0.1", locale: locale)! + Money.parse("0.2", locale: locale)!, Decimal(string: "0.3")!)
        XCTAssertEqual(Money.parse("12,345", locale: Locale(identifier: "de_DE")), Decimal(string: "12.345"))
        XCTAssertNil(Money.parse("1,000", locale: locale))
        XCTAssertNil(Money.parse("-2", locale: locale))
        XCTAssertNil(Money.parse("1.2345", locale: locale))
        XCTAssertNil(Money.parse("9999999999999", locale: locale))
        let data = Data(#"{"year":2026,"month":3,"day":8}"#.utf8)
        let day = try JSONDecoder().decode(Day.self, from: data)
        XCTAssertTrue(day.isValid)
        XCTAssertEqual(Day(day.date), day)
        let bad = try JSONDecoder().decode(Day.self, from: Data(#"{"year":2026,"month":2,"day":30}"#.utf8))
        XCTAssertFalse(bad.isValid)
    }
    func testPersistenceStageAndDeletion() async throws {
        let directory = try temporary()
        var companyID: UUID!; var contactID: UUID!; var dealID: UUID!; var taskID: UUID!
        do {
            let s = try CRMStore(root: directory)
            var c = RecordData(kind: .company); c.name = "Company"; companyID = c.id; try s.save(c)
            var p = RecordData(kind: .contact); p.name = "Alex"; p.companyID = c.id; contactID = p.id; try s.save(p)
            var d = RecordData(kind: .deal); d.name = "Website"; d.companyID = c.id; d.contactID = p.id; dealID = d.id
            let deal = try s.save(d); s.move(deal, to: .proposal)
            var t = RecordData(kind: .task); t.name = "Follow up"; t.contactID = p.id; t.dealID = d.id; taskID = t.id; try s.save(t)
        }
        let reopened = try CRMStore(root: directory)
        XCTAssertEqual(reopened.record(dealID)?.stage, .proposal)
        XCTAssertEqual(reopened.record(dealID)?.company?.id, companyID)
        await reopened.delete(try XCTUnwrap(reopened.record(companyID)))
        XCTAssertNotNil(reopened.record(dealID)); XCTAssertNil(reopened.record(dealID)?.company)
        XCTAssertNil(reopened.record(contactID)?.company)
        await reopened.delete(try XCTUnwrap(reopened.record(contactID)))
        XCTAssertNotNil(reopened.record(taskID)); XCTAssertNil(reopened.record(taskID)?.contact)
        XCTAssertNil(reopened.record(dealID)?.contact)
        XCTAssertEqual(reopened.record(taskID)?.deal?.id, dealID)
        await reopened.delete(try XCTUnwrap(reopened.record(dealID)))
        XCTAssertNotNil(reopened.record(taskID)); XCTAssertNil(reopened.record(taskID)?.deal)
        XCTAssertNil(reopened.errorMessage)
    }
    func testAttachmentImportDuplicatesFailureAndDelete() async throws {
        let s = try store()
        var d = RecordData(kind: .contact); d.name = "Alex"
        let owner = try s.save(d)
        let source = try sampleFile(temporary())
        await s.importFiles([source, source], owner: owner)
        XCTAssertEqual(owner.attachments.count, 2)
        XCTAssertEqual(Set(owner.attachments.map(\.relativePath)).count, 2)
        XCTAssertEqual(Set(owner.attachments.map(\.filename)), ["proposal.txt"])
        await s.importFiles([source.appendingPathComponent("missing")], owner: owner)
        XCTAssertEqual(owner.attachments.count, 2)
        XCTAssertNotNil(s.errorMessage)
        let link = source.deletingLastPathComponent().appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        await s.importFiles([link], owner: owner)
        XCTAssertEqual(owner.attachments.count, 2)
        let paths = owner.attachments.map(\.relativePath)
        await s.delete(owner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        for path in paths { XCTAssertFalse(FileManager.default.fileExists(atPath: s.root.appendingPathComponent("Attachments/" + path).path)) }
        XCTAssertEqual(try s.context.fetchCount(FetchDescriptor<Attachment>()), 0)
    }
    func testBackupRoundTripAndSafetyBackup() async throws {
        let s = try store(); try s.loadSamples()
        let owner = try XCTUnwrap(s.all(.deal).first)
        let id = owner.id
        let source = try sampleFile(temporary())
        await s.importFiles([source], owner: owner)
        let original = s.snapshot()
        let backup = try temporary().appendingPathComponent("test.lightcrmbackup")
        try await s.vault.export(original, to: backup)
        let validated = try await s.vault.validate(backup)
        XCTAssertEqual(validated.records.count, original.records.count)
        s.move(owner, to: .lost)
        let safety = try await s.replaceFromBackup(backup)
        XCTAssertEqual(s.snapshot().records.sorted { $0.id.uuidString < $1.id.uuidString }, original.records.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(s.record(id)?.attachments.count, 1)
        let restored = try XCTUnwrap(s.record(id)?.attachments.first)
        let file = try await s.vault.fileURL(restored.relativePath)
        XCTAssertEqual(file.pathExtension, "txt")
        XCTAssertEqual(try Data(contentsOf: file), try Data(contentsOf: source))
        let safetyData = try await s.vault.validate(safety)
        XCTAssertEqual(safetyData.records.first { $0.id == id }?.stage, .lost)
        let reopened = try CRMStore(root: s.root)
        XCTAssertEqual(reopened.record(id)?.attachments.count, 1)
    }
    func testFailedRestorePreservesRecordsAndFiles() async throws {
        let s = try store(); try s.loadSamples()
        let owner = try XCTUnwrap(s.all(.deal).first)
        await s.importFiles([try sampleFile(temporary())], owner: owner)
        let before = s.snapshot()
        let backup = try temporary().appendingPathComponent("test.lightcrmbackup")
        try await s.vault.export(before, to: backup)
        do {
            _ = try await s.replaceFromBackup(backup, beforeCommit: { throw CRMError.invalid("Injected save failure") })
            XCTFail("Restore should have failed")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Injected")) }
        XCTAssertEqual(s.snapshot().records, before.records)
        XCTAssertEqual(s.snapshot().attachments, before.attachments)
        for a in before.attachments { _ = try await s.vault.fileURL(a.relativePath) }
        let reopened = try CRMStore(root: s.root)
        XCTAssertEqual(reopened.records.count, before.records.count)
    }
    func testUnsafePathsAndInvalidRelationshipsRejected() throws {
        let directory = try temporary()
        for path in ["../outside", "/etc/passwd", "a/../../outside", "a//b", "a/./b", "a\\b", "a:b"] {
            XCTAssertThrowsError(try FileVault.safeURL(path, in: directory), path)
        }
        let outside = try temporary()
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try FileVault.safeURL("link/file", in: directory))
        var bad = RecordData(kind: .deal); bad.name = "Invalid"; bad.companyID = UUID()
        XCTAssertThrowsError(try FileVault.validateRecords(Snapshot(records: [bad], attachments: [], currency: "USD")))
        bad.companyID = nil
        XCTAssertThrowsError(try FileVault.validateRecords(Snapshot(records: [bad, bad], attachments: [], currency: "USD")))
    }
    func testCorruptAndUnsupportedBackupsPreserveExistingData() async throws {
        let s = try store(); try s.loadSamples()
        let before = s.snapshot()
        let backup = try temporary().appendingPathComponent("test.lightcrmbackup")
        try await s.vault.export(before, to: backup)
        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
        manifest.version = 999
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        do { _ = try await s.replaceFromBackup(backup); XCTFail("Unsupported format accepted") } catch { }
        XCTAssertEqual(s.snapshot().records, before.records)
        manifest.version = 1; try JSONEncoder().encode(manifest).write(to: manifestURL)
        try Data("corrupt".utf8).write(to: backup.appendingPathComponent("records.json"))
        do { _ = try await s.replaceFromBackup(backup); XCTFail("Corrupt records accepted") } catch { }
        XCTAssertEqual(s.snapshot().records, before.records)
    }
    private func rewrite(_ snapshot: Snapshot, package: URL) throws {
        let records = try JSONEncoder().encode(snapshot)
        try records.write(to: package.appendingPathComponent("records.json"))
        let digest = SHA256.hash(data: records).map { String(format: "%02x", $0) }.joined()
        let manifest = BackupManifest(recordCount: snapshot.records.count, attachmentCount: snapshot.attachments.count, recordsSHA256: digest)
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
    }
    func testBackupPathTraversalAndSymlinkAreRejectedBeforeReplacement() async throws {
        let s = try store(); try s.loadSamples()
        await s.importFiles([try sampleFile(temporary())], owner: try XCTUnwrap(s.all(.contact).first))
        let before = s.snapshot()
        let backup = try temporary().appendingPathComponent("unsafe.lightcrmbackup")
        try await s.vault.export(before, to: backup)
        let original = try await s.vault.validate(backup)
        var malicious = original
        malicious.attachments[0].relativePath = "../../outside.txt"
        try rewrite(malicious, package: backup)
        do { _ = try await s.replaceFromBackup(backup); XCTFail("Traversal accepted") } catch { }
        XCTAssertEqual(s.snapshot().records, before.records)
        XCTAssertEqual(s.snapshot().attachments, before.attachments)
        try rewrite(original, package: backup)
        let link = backup.appendingPathComponent("unreferenced-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: try temporary())
        do { _ = try await s.replaceFromBackup(backup); XCTFail("Symlink accepted") } catch { }
        XCTAssertEqual(s.snapshot().records, before.records)
    }
    func testMissingBackupDocumentAndFailedCopyPreserveWorkspace() async throws {
        let s = try store(); try s.loadSamples()
        let contact = try XCTUnwrap(s.all(.contact).first)
        let source = try sampleFile(temporary())
        await s.importFiles([source], owner: contact)
        let before = s.snapshot()
        let backup = try temporary().appendingPathComponent("missing.lightcrmbackup")
        try await s.vault.export(before, to: backup)
        let portable = try await s.vault.validate(backup)
        try FileManager.default.removeItem(at: backup.appendingPathComponent("attachments/" + portable.attachments[0].relativePath))
        do { _ = try await s.replaceFromBackup(backup); XCTFail("Missing file accepted") } catch { }
        XCTAssertEqual(s.snapshot().attachments, before.attachments)
        let blockedRoot = try temporary().appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blockedRoot)
        let blockedVault = FileVault(root: blockedRoot)
        do { _ = try await blockedVault.importFile(source, ownerID: contact.id); XCTFail("Copy should fail") } catch { }
        XCTAssertEqual(try Data(contentsOf: source), Data("A fictional proposal.\n".utf8))
        XCTAssertEqual(s.snapshot().records, before.records)
    }
    func testRestoreIntoAnotherWorkspacePreservesRelationships() async throws {
        let source = try store(); try source.loadSamples()
        let owner = try XCTUnwrap(source.all(.deal).first)
        await source.importFiles([try sampleFile(temporary())], owner: owner)
        let backup = try temporary().appendingPathComponent("portable.lightcrmbackup")
        try await source.vault.export(source.snapshot(), to: backup)
        let destination = try store()
        var old = RecordData(kind: .company); old.name = "Replace me"; try destination.save(old)
        _ = try await destination.replaceFromBackup(backup)
        XCTAssertNil(destination.record(old.id))
        XCTAssertEqual(destination.records.count, source.records.count)
        let restored = try XCTUnwrap(destination.record(owner.id))
        XCTAssertEqual(restored.company?.id, owner.company?.id)
        XCTAssertEqual(restored.contact?.id, owner.contact?.id)
        XCTAssertEqual(restored.attachments.count, 1)
        _ = try await destination.vault.fileURL(restored.attachments[0].relativePath)
    }
    func testSampleDataCannotDuplicate() throws {
        let s = try store(); try s.loadSamples(); let count = s.records.count
        XCTAssertThrowsError(try s.loadSamples()); XCTAssertEqual(s.records.count, count)
    }
}
