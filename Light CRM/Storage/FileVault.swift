import Foundation
import CryptoKit
import UniformTypeIdentifiers

nonisolated struct BackupManifest: Codable, Sendable {
    var format = "LightCRM"
    var version = 1
    var createdAt = Date.now
    var recordCount: Int
    var attachmentCount: Int
    var recordsSHA256: String
}

/// File copying and streaming checksums stay off the UI actor. Callers serialize
/// mutations while taking snapshots so records and attachments describe one instant.
actor FileVault {
    let root: URL
    private let fm = FileManager.default
    init(root: URL) { self.root = root }

    static func safeURL(_ path: String, in base: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") && !$0.contains("\0") }),
              !path.hasPrefix("/"), path.utf8.count < 1024 else {
            throw CRMError.invalid("Unsafe attachment path: \(path)")
        }
        var url = base
        for part in parts {
            url.appendPathComponent(String(part))
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
                throw CRMError.invalid("Symbolic links are not allowed in attachments or backups.")
            }
        }
        let resolvedBase = base.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resolvedBase) else {
            throw CRMError.invalid("The attachment is outside its storage directory.")
        }
        return url
    }

    private static func regularFile(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            throw CRMError.invalid("“\(url.lastPathComponent)” is not a regular file. Choose individual documents, not folders, aliases, or symbolic links.")
        }
        let values = try url.resourceValues(forKeys: [.isAliasFileKey])
        guard values.isAliasFile != true else { throw CRMError.invalid("Finder aliases cannot be imported. Choose the original document.") }
        return size.int64Value
    }

    private static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func importFile(_ source: URL, ownerID: UUID) throws -> AttachmentData {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        _ = try Self.regularFile(source)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let ext = source.pathExtension.filter { $0.isLetter || $0.isNumber }.prefix(20)
        let path = id.uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let destination = try Self.safeURL(path, in: root)
        do {
            try fm.copyItem(at: source, to: destination)
            let size = try Self.regularFile(destination)
            return AttachmentData(id: id, ownerID: ownerID, filename: source.lastPathComponent,
                                  relativePath: path, size: size,
                                  type: UTType(filenameExtension: source.pathExtension)?.identifier ?? "public.data", addedAt: .now)
        } catch { try? fm.removeItem(at: destination); throw error }
    }

    func remove(_ paths: [String]) throws {
        var failures: [String] = []
        for path in paths {
            do {
                let url = try Self.safeURL(path, in: root)
                if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            } catch { failures.append(path) }
        }
        if !failures.isEmpty { throw CRMError.invalid("The records were updated, but \(failures.count) unused managed file(s) could not be removed. Check storage permissions. Original files were not changed.") }
    }

    func fileURL(_ path: String) throws -> URL {
        let url = try Self.safeURL(path, in: root)
        guard fm.fileExists(atPath: url.path) else { throw CRMError.invalid("This managed document is missing. Restore a backup or remove its entry and import the original again.") }
        _ = try Self.regularFile(url)
        return url
    }

    func export(_ snapshot: Snapshot, to destination: URL) throws {
        guard !fm.fileExists(atPath: destination.path) else { throw CRMError.invalid("A backup already exists at that location. Choose a new name; existing backups are never overwritten.") }
        let access = destination.deletingLastPathComponent().startAccessingSecurityScopedResource()
        defer { if access { destination.deletingLastPathComponent().stopAccessingSecurityScopedResource() } }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".lightcrm-\(UUID().uuidString)")
        do {
            let documents = temporary.appendingPathComponent("attachments")
            try fm.createDirectory(at: documents, withIntermediateDirectories: true)
            var portable = snapshot
            for i in portable.attachments.indices {
                let original = portable.attachments[i]
                let source = try Self.safeURL(original.relativePath, in: root)
                guard try Self.regularFile(source) == original.size else { throw CRMError.invalid("The managed file “\(original.filename)” changed or is missing. Reimport it before backing up.") }
                let path = original.id.uuidString
                let target = try Self.safeURL(path, in: documents)
                try fm.copyItem(at: source, to: target)
                portable.attachments[i].relativePath = path
                portable.attachments[i].sha256 = try Self.digest(target)
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let records = temporary.appendingPathComponent("records.json")
            try encoder.encode(portable).write(to: records, options: .atomic)
            let manifest = BackupManifest(recordCount: portable.records.count, attachmentCount: portable.attachments.count, recordsSHA256: try Self.digest(records))
            try encoder.encode(manifest).write(to: temporary.appendingPathComponent("manifest.json"), options: .atomic)
            try fm.moveItem(at: temporary, to: destination)
        } catch { try? fm.removeItem(at: temporary); throw error }
    }

    static func validateRecords(_ snapshot: Snapshot) throws {
        guard Locale.commonISOCurrencyCodes.contains(snapshot.currency) else { throw CRMError.invalid("Backup currency is unsupported.") }
        let ids = snapshot.records.map(\.id)
        let attachmentIDs = snapshot.attachments.map(\.id)
        guard Set(ids).count == ids.count, Set(attachmentIDs).count == attachmentIDs.count,
              Set(snapshot.attachments.map(\.relativePath)).count == snapshot.attachments.count else {
            throw CRMError.invalid("The backup contains duplicate record identifiers or attachment paths.")
        }
        let records = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0) })
        for record in snapshot.records {
            guard !(record.name + record.lastName).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.due?.isValid != false, record.launch?.isValid != false,
                  Money.parse(record.amount, locale: Locale(identifier: "en_US_POSIX")) != nil else {
                throw CRMError.invalid("The backup contains invalid names, dates, or monetary values.")
            }
            if let id = record.companyID {
                guard [.contact, .deal].contains(record.kind), records[id]?.kind == .company else { throw CRMError.invalid("Invalid company relationship in backup.") }
            }
            if let id = record.contactID {
                guard [.deal, .task].contains(record.kind), records[id]?.kind == .contact else { throw CRMError.invalid("Invalid contact relationship in backup.") }
            }
            if let id = record.dealID {
                guard record.kind == .task, records[id]?.kind == .deal else { throw CRMError.invalid("Invalid deal relationship in backup.") }
            }
        }
        for attachment in snapshot.attachments {
            guard let owner = records[attachment.ownerID], [.contact, .deal].contains(owner.kind),
                  attachment.size >= 0, !attachment.filename.isEmpty else { throw CRMError.invalid("An attachment has an invalid owner or metadata.") }
        }
    }

    func validate(_ package: URL) throws -> Snapshot {
        let access = package.startAccessingSecurityScopedResource()
        defer { if access { package.stopAccessingSecurityScopedResource() } }
        let attributes = try fm.attributesOfItem(atPath: package.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw CRMError.invalid("Choose a Light CRM backup folder (.lightcrmbackup).") }
        // Reject all symlinks, including unreferenced files and the package root.
        guard let enumerator = fm.enumerator(at: package, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { throw CRMError.invalid("The backup cannot be read.") }
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw CRMError.invalid("Backups containing symbolic links are not supported.") }
        }
        let manifestURL = try Self.safeURL("manifest.json", in: package)
        let recordsURL = try Self.safeURL("records.json", in: package)
        guard try Self.regularFile(manifestURL) < 1_048_576, try Self.regularFile(recordsURL) < 100_000_000 else { throw CRMError.invalid("The backup metadata exceeds the supported size.") }
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == "LightCRM", manifest.version == 1 else { throw CRMError.invalid("Unsupported backup format. This app supports Light CRM backup version 1.") }
        guard try Self.digest(recordsURL) == manifest.recordsSHA256 else { throw CRMError.invalid("Backup records failed their integrity check. Select an intact backup.") }
        let snapshot = try decoder.decode(Snapshot.self, from: Data(contentsOf: recordsURL))
        guard snapshot.records.count == manifest.recordCount, snapshot.attachments.count == manifest.attachmentCount else { throw CRMError.invalid("Backup record counts do not match the manifest.") }
        try Self.validateRecords(snapshot)
        for attachment in snapshot.attachments {
            let file = try Self.safeURL("attachments/" + attachment.relativePath, in: package)
            guard try Self.regularFile(file) == attachment.size, try Self.digest(file) == attachment.sha256 else {
                throw CRMError.invalid("“\(attachment.filename)” failed its size or integrity check. Nothing has been replaced.")
            }
        }
        return snapshot
    }

    /// Copies a validated package into a fresh generation. Existing paths remain
    /// untouched until the database transaction commits; failures remove only staging.
    func stage(_ package: URL) throws -> Snapshot {
        let access = package.startAccessingSecurityScopedResource()
        defer { if access { package.stopAccessingSecurityScopedResource() } }
        var snapshot = try validate(package)
        let generation = UUID().uuidString
        let staging = root.appendingPathComponent(generation)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for i in snapshot.attachments.indices {
                let attachment = snapshot.attachments[i]
                let source = try Self.safeURL("attachments/" + attachment.relativePath, in: package)
                let ext = URL(fileURLWithPath: attachment.filename).pathExtension.filter { $0.isLetter || $0.isNumber }.prefix(20)
                let path = generation + "/" + attachment.id.uuidString + (ext.isEmpty ? "" : ".\(ext)")
                let target = try Self.safeURL(path, in: root)
                try fm.copyItem(at: source, to: target)
                guard try Self.digest(target) == attachment.sha256 else { throw CRMError.invalid("An attachment changed during restore. Current data is unchanged.") }
                snapshot.attachments[i].relativePath = path
            }
            return snapshot
        } catch { try? fm.removeItem(at: staging); throw error }
    }
}
