import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RecordInspector: View {
    let store: CRMStore
    let record: CRMRecord
    let edit: () -> Void
    let delete: () -> Void
    let open: (CRMRecord) -> Void
    @State private var attachmentToDelete: UUID?
    @State private var dropTargeted = false
    private var related: [CRMRecord] {
        store.records.filter {
            $0.company?.id == record.id || $0.contact?.id == record.id || $0.deal?.id == record.id ||
            (record.kind == .company && $0.kind == .task && ($0.deal?.company?.id == record.id || $0.contact?.company?.id == record.id))
        }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(record.kind.title, systemImage: record.kind.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Design.blue)
                        Spacer()
                        Button(action: delete) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Design.red).help("Delete \(record.kind.title.lowercased())")
                    }
                    Text(record.title).font(.system(size: 24, weight: .bold, design: .rounded)).tracking(-0.4).textSelection(.enabled)
                    if record.kind == .deal { StageBadge(stage: record.stage) }
                    Button(action: edit) { Label("Edit details", systemImage: "pencil") }.buttonStyle(FlatButtonStyle())
                }
                details
                if !record.notes.isEmpty { section("Notes") { Text(record.notes).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } }
                if !related.isEmpty {
                    section("Related records · \(related.count)") {
                        ForEach(related) { r in
                            Button { open(r) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: r.kind.symbol).foregroundStyle(Design.blue)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(r.title).font(Design.control).multilineTextAlignment(.leading)
                                        Text(r.kind == .task ? r.completed ? "Completed task" : "Open task" : r.kind.title).font(.caption).foregroundStyle(Design.secondaryText)
                                    }
                                    Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.caption)
                                }.padding(10).background(Design.background, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if record.kind == .contact || record.kind == .deal { documents }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Created \(record.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    Text("Updated \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                }.font(.system(size: 10)).foregroundStyle(Design.secondaryText)
            }.padding(20)
        }.background(Design.muted)
            .confirmationDialog("Delete managed document?", isPresented: Binding(get: { attachmentToDelete != nil }, set: { if !$0 { attachmentToDelete = nil } }), titleVisibility: .visible, presenting: attachmentToDelete) { id in
                Button("Delete Managed Copy", role: .destructive) {
                    if let a = record.attachments.first(where: { $0.id == id }) { Task { await store.deleteAttachment(a) } }
                    attachmentToDelete = nil
                }
            } message: { _ in Text("This removes the document from Light CRM and deletes its managed copy. Your original imported file is not changed.") }
    }
    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let company = record.company { linked("Company", company) }
            if let contact = record.contact { linked("Contact", contact) }
            if let deal = record.deal { linked("Deal", deal) }
            if !record.email.isEmpty {
                section("Email") {
                    Button(record.email) {
                        var components = URLComponents(); components.scheme = "mailto"; components.path = record.email
                        if let url = components.url { launch(url) }
                    }.buttonStyle(.link).textSelection(.enabled)
                }
            }
            if !record.phone.isEmpty { section("Phone") { Text(record.phone).textSelection(.enabled) } }
            if !record.website.isEmpty, let url = safeWebsite(record.website) {
                section("Website") { Button(record.website) { launch(url) }.buttonStyle(.link) }
            }
            if record.kind == .deal {
                section("Estimated value · \(store.currency)") { Text(store.money(record.value)).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit() }
                section("Service") { Text(record.serviceRaw) }
                Picker("Stage", selection: Binding(get: { record.stage }, set: { store.move(record, to: $0) })) {
                    ForEach(DealStage.allCases) { Text($0.rawValue).tag($0) }
                }
                section("Next action") { Text(record.nextAction.isEmpty ? "No next action set" : record.nextAction) }
                section("Follow-up") { DueLabel(day: record.due, overdue: record.isOverdue) }
                section("Target launch") { DueLabel(day: record.launch) }
            }
            if record.kind == .task {
                Button { store.toggle(record) } label: { Label(record.completed ? "Completed · mark incomplete" : "Mark complete", systemImage: record.completed ? "checkmark.circle.fill" : "circle") }.buttonStyle(FlatButtonStyle())
                section("Due date") { DueLabel(day: record.due, overdue: record.isOverdue) }
            }
        }
    }
    private var documents: some View {
        section("Documents · \(record.attachments.count)") {
            ForEach(record.attachments.sorted { $0.addedAt > $1.addedAt }) { attachment in
                VStack(alignment: .leading, spacing: 6) {
                    Button { openDocument(attachment, reveal: false) } label: {
                        Label(attachment.filename, systemImage: "doc").font(Design.control).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain).help("Open in default application")
                    Text("\(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file)) · \(attachment.addedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10)).foregroundStyle(Design.secondaryText)
                    HStack {
                        Button("Reveal in Finder") { openDocument(attachment, reveal: true) }.buttonStyle(.link)
                        Spacer()
                        Button { attachmentToDelete = attachment.id } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Design.red).help("Remove \(attachment.filename)")
                    }.font(.system(size: 11))
                }.padding(10).background(Design.background, in: RoundedRectangle(cornerRadius: 6))
            }
            Button(action: importDocuments) { Label("Import documents…", systemImage: "plus") }.buttonStyle(FlatButtonStyle())
            Text("Or drop files here. Original files stay where they are.").font(.system(size: 11)).foregroundStyle(Design.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 50).padding(8)
                .background(dropTargeted ? Design.selection : Design.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(dropTargeted ? Design.blue : Design.border, style: StrokeStyle(lineWidth: 1, dash: [4])))
                .dropDestination(for: URL.self) { urls, _ in
                    guard !store.busy, !urls.isEmpty else { return false }
                    let files = urls.filter(\.isFileURL)
                    guard files.count == urls.count else { store.errorMessage = "Only local files can be imported. Download the document first, then import it."; return false }
                    Task { await store.importFiles(files, owner: record) }; return true
                } isTargeted: { dropTargeted = $0 }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Design.secondaryText)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func linked(_ label: String, _ target: CRMRecord) -> some View {
        section(label) { Button { open(target) } label: { Label(target.title, systemImage: "arrow.up.right") }.buttonStyle(.link) }
    }
    private func launch(_ url: URL) {
        if !NSWorkspace.shared.open(url) { store.errorMessage = "No application could open this link. Check your default email or browser application." }
    }
    private func importDocuments() {
        let panel = NSOpenPanel(); panel.title = "Import documents into Light CRM"; panel.allowsMultipleSelection = true
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { let urls = panel.urls; Task { await store.importFiles(urls, owner: record) } }
    }
    private func openDocument(_ attachment: Attachment, reveal: Bool) {
        let path = attachment.relativePath
        Task {
            do {
                let url = try await store.vault.fileURL(path)
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                else if !NSWorkspace.shared.open(url) { throw CRMError.invalid("No application could open “\(attachment.filename)”. Use Reveal in Finder to choose an application.") }
            } catch { store.report(error) }
        }
    }
}
