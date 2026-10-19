import SwiftUI

struct RecordEditor: View {
    let store: CRMStore
    let original: RecordData
    let isNew: Bool
    let saved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecordData
    @State private var amountText: String
    @State private var discard = false
    @State private var error: String?
    @FocusState private var notesFocused: Bool
    init(store: CRMStore, original: RecordData, isNew: Bool, saved: @escaping (UUID) -> Void) {
        self.store = store; self.original = original; self.isNew = isNew; self.saved = saved
        _draft = State(initialValue: original)
        _amountText = State(initialValue: Money.editable(Decimal(string: original.amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0))
    }
    private var dirty: Bool { draft != original || amountText != Money.editable(Decimal(string: original.amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0) }
    private var validation: String? {
        if (draft.name + (draft.kind == .contact ? draft.lastName : "")).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return draft.kind == .contact ? "Enter a first or last name." : "Enter a \(draft.kind == .deal ? "project name" : draft.kind == .task ? "task title" : "company name")."
        }
        if draft.kind == .deal && Money.parse(amountText) == nil { return "Enter a nonnegative amount up to 999,999,999,999, with up to three decimal places. Use your locale’s decimal separator and no grouping separators." }
        if !draft.email.isEmpty && (draft.email.contains(" ") || !draft.email.contains("@") || draft.email.hasPrefix("@") || draft.email.hasSuffix("@")) { return "Enter an email address such as alex@example.com, or leave it empty." }
        if !draft.website.isEmpty && safeWebsite(draft.website) == nil { return "Enter a valid http or https website, such as https://example.com." }
        return nil
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(isNew ? "New" : "Edit") \(draft.kind.title.lowercased())").font(Design.title).tracking(-0.5)
                    Text("The details that keep work moving.").foregroundStyle(Design.secondaryText)
                }
                Spacer()
            }.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fields
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(Design.control)
                        TextEditor(text: $draft.notes).font(Design.body).scrollContentBackground(.hidden)
                            .padding(8).frame(height: 120).background(Design.muted, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(notesFocused ? Design.blue : .clear, lineWidth: 2))
                            .focused($notesFocused).accessibilityLabel("Notes")
                    }
                    if let message = error ?? validation {
                        Label(message, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(error == nil ? Design.secondaryText : Design.red).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).buttonStyle(FlatButtonStyle())
                Spacer()
                Text("Saved only on this Mac").font(.caption).foregroundStyle(Design.secondaryText)
                Button("Save \(draft.kind.title)", action: save).keyboardShortcut(.defaultAction)
                    .buttonStyle(FlatButtonStyle(primary: true)).disabled(validation != nil)
            }.padding(20).background(Design.muted)
        }.frame(width: 600, height: 720).background(Design.background).foregroundStyle(Design.foreground)
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Discard unsaved changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { EditSession.hasChanges = false; dismiss() }
                Button("Keep Editing", role: .cancel) { }
            }
            .onChange(of: dirty) { _, value in EditSession.hasChanges = value }
            .onDisappear { EditSession.hasChanges = false }
    }
    @ViewBuilder private var fields: some View {
        switch draft.kind {
        case .contact:
            HStack(alignment: .top, spacing: 16) {
                Field(label: "First name", placeholder: "Alex", text: $draft.name)
                Field(label: "Last name", placeholder: "Rivera", text: $draft.lastName)
            }
            Field(label: "Email", placeholder: "alex@example.com", text: $draft.email)
            Field(label: "Phone", placeholder: "+1 415 555 0100", text: $draft.phone)
            relation("Company", kind: .company, selection: $draft.companyID)
        case .company:
            Field(label: "Company name", placeholder: "Juniper Studio", text: $draft.name)
            Field(label: "Website", placeholder: "https://example.com", text: $draft.website)
        case .deal:
            Field(label: "Project name", placeholder: "A new website for Juniper", text: $draft.name)
            HStack(spacing: 16) {
                relation("Company", kind: .company, selection: $draft.companyID)
                relation("Primary contact", kind: .contact, selection: $draft.contactID)
            }
            HStack(spacing: 16) {
                Picker("Service", selection: $draft.service) { ForEach(Service.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Stage", selection: $draft.stage) { ForEach(DealStage.allCases) { Text($0.rawValue).tag($0) } }
            }
            Field(label: "Estimated value (\(store.currency))", placeholder: "8500", text: $amountText)
            OptionalDayPicker(title: "Target launch", day: $draft.launch)
            Field(label: "Next action", placeholder: "Follow up on the proposal", text: $draft.nextAction)
            OptionalDayPicker(title: "Follow-up date", day: $draft.due)
        case .task:
            Field(label: "Task title", placeholder: "Send the revised proposal", text: $draft.name)
            OptionalDayPicker(title: "Due date", day: $draft.due)
            Toggle("Completed", isOn: $draft.completed)
            relation("Linked contact", kind: .contact, selection: $draft.contactID)
            relation("Linked deal", kind: .deal, selection: $draft.dealID)
        }
    }
    private func relation(_ title: String, kind: RecordKind, selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Design.control)
            Picker(title, selection: selection) {
                Text("None").tag(nil as UUID?)
                ForEach(store.all(kind)) { Text($0.title).tag(Optional($0.id)) }
            }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(title)
        }
    }
    private func cancel() { if dirty { discard = true } else { dismiss() } }
    private func save() {
        guard validation == nil else { return }
        if draft.kind == .deal, let money = Money.parse(amountText) { draft.amount = Money.canonical(money) }
        do {
            let record = try store.save(draft); EditSession.hasChanges = false; saved(record.id); dismiss()
        } catch { self.error = "Couldn’t save: \(error.localizedDescription)" }
    }
}

func safeWebsite(_ text: String) -> URL? {
    let candidate = text.contains("://") ? text : "https://" + text
    guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host, host.contains("."), !text.contains(" ") else { return nil }
    return url
}
