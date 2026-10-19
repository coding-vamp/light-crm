import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: CRMStore
    @State private var section = "Overview"
    @State private var selection: UUID?
    @State private var query = ""
    @State private var editor: RecordData?
    @State private var inspectorVisible = true
    @State private var stageFilter = "All stages"
    @State private var taskFilter = "Upcoming"
    @State private var restoreURL: URL?
    @State private var currencySheet = false
    @State private var deleteID: UUID?
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("dealsView") private var dealsView = "Board"
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var kind: RecordKind? { RecordKind.allCases.first { $0.plural == section } }
    private var selected: CRMRecord? { store.record(selection) }
    private var filtered: [CRMRecord] {
        guard let kind else { return [] }
        return store.all(kind).filter { r in
            let matches = query.isEmpty || [r.title, r.email, r.phone, r.website, r.notes, r.client, r.nextAction].joined(separator: " ").localizedStandardContains(query)
            let stage = kind != .deal || stageFilter == "All stages" || r.stageRaw == stageFilter
            let task = kind != .task || (taskFilter == "Completed" ? r.completed : taskFilter == "Overdue" ? r.isOverdue : !r.completed)
            return matches && stage && task
        }
    }
    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 204, max: 240)
        } detail: {
            VStack(spacing: 0) {
                header
                if store.busy {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Working with local files…").font(Design.control); Spacer() }
                        .padding(12).background(Design.selection)
                }
                if section == "Overview" {
                    OverviewView(store: store, open: navigate, add: { editor = RecordData(kind: .deal) })
                } else {
                    filters
                    HSplitView {
                        mainContent.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                        if inspectorVisible, let selected {
                            RecordInspector(store: store, record: selected, edit: { editor = RecordData(selected) }, delete: { deleteID = selected.id }, open: navigate)
                                .frame(minWidth: 290, idealWidth: 330, maxWidth: 440)
                                .id(selected.id)
                        }
                    }
                }
            }.background(Design.background)
        }
        .font(Design.body).foregroundStyle(Design.foreground)
        .frame(minWidth: 960, minHeight: 620)
        .tint(Design.blue)
        .preferredColorScheme(appearance == "Light" ? .light : appearance == "Dark" ? .dark : nil)
        .disabled(store.busy)
        .sheet(item: $editor) { draft in
            RecordEditor(store: store, original: draft, isNew: store.record(draft.id) == nil) { saved in
                selection = saved; inspectorVisible = true
            }
        }
        .sheet(isPresented: $currencySheet) { CurrencyEditor(store: store) }
        .alert("Workspace error", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .alert("Workspace updated", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
        .confirmationDialog("Delete record?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible, presenting: deleteID) { id in
            Button("Delete Record", role: .destructive) {
                if let r = store.record(id) { selection = nil; Task { await store.delete(r) } }
                deleteID = nil
            }
        } message: { id in Text(store.record(id).map(store.deletionExplanation) ?? "") }
        .confirmationDialog("Replace this workspace?", isPresented: Binding(get: { restoreURL != nil }, set: { if !$0 { restoreURL = nil } }), titleVisibility: .visible, presenting: restoreURL) { url in
            Button("Validate and Replace", role: .destructive) {
                restoreURL = nil; selection = nil
                Task { await store.restore(from: url) }
            }
        } message: { _ in
            Text("Restore replaces all current contacts, companies, deals, tasks, documents, and the currency setting. The entire backup is validated first, and a safety backup of this workspace is saved locally before replacement. Keep the app open until it finishes.")
        }
        .onChange(of: section) { _, _ in query = ""; selection = nil }
        .onChange(of: store.busy) { _, value in EditSession.busy = value }
        .onReceive(NotificationCenter.default.publisher(for: .crmNew)) { _ in newRecord() }
        .onReceive(NotificationCenter.default.publisher(for: .crmFind)) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .crmExport)) { _ in if canPresent { exportBackup() } }
        .onReceive(NotificationCenter.default.publisher(for: .crmRestore)) { _ in if canPresent { chooseRestore() } }
        .onReceive(NotificationCenter.default.publisher(for: .crmCurrency)) { _ in if canPresent { currencySheet = true } }
    }
    private var canPresent: Bool { !store.busy && editor == nil && !currencySheet }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "square.split.2x2.fill").font(.system(size: 23, weight: .bold)).foregroundStyle(Design.primaryFill)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Light CRM").font(Design.heading)
                    Text("YOUR AGENCY, IN FOCUS").font(.system(size: 8, weight: .bold)).tracking(1)
                        .foregroundStyle(Design.secondaryText)
                }
            }.padding(.top, 20).padding(.horizontal, 16)
            List(selection: $section) {
                Label("Overview", systemImage: "square.grid.2x2").tag("Overview")
                ForEach(RecordKind.allCases) { kind in
                    Label(kind.plural, systemImage: kind.symbol).tag(kind.plural)
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive").foregroundStyle(Design.green)
                    Text("Local workspace").font(Design.control)
                }
                Text("One agency. All the details.\nStored only on this Mac.")
                    .font(.system(size: 11)).foregroundStyle(Design.secondaryText)
                Menu {
                    Button("Export Backup…", action: exportBackup)
                    Button("Restore Backup…", action: chooseRestore)
                    Button("Show Local Storage") { NSWorkspace.shared.open(store.root) }
                    Divider()
                    Button("Currency: \(store.currency)…") { currencySheet = true }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) }
                    }
                    if store.isEmpty { Button("Load Sample Data", action: loadSamples) }
                } label: { Label("Workspace", systemImage: "gearshape") }
                .menuStyle(.borderlessButton)
            }.padding(16)
        }.background(Design.muted)
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section).font(Design.title).tracking(-0.6)
                Text(section == "Overview" ? "A clear view of what’s next." : "\(store.all(kind ?? .contact).count) \(section.lowercased()) · \(store.currency)")
                    .foregroundStyle(Design.secondaryText)
            }
            Spacer(minLength: 12)
            if section != "Overview" {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Design.secondaryText)
                    TextField("Search \(section.lowercased())", text: $query).textFieldStyle(.plain).focused($searchFocused)
                        .accessibilityLabel("Search \(section)")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search") }
                }.padding(10).frame(width: 210).background(Design.muted, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(searchFocused ? Design.blue : .clear, lineWidth: 2))
            }
            Button(action: newRecord) { Label("New \(kind?.title.lowercased() ?? "deal")", systemImage: "plus") }
                .buttonStyle(FlatButtonStyle(primary: true)).help("Create a record (⌘N)")
        }.padding(24)
    }
    private var filters: some View {
        HStack(spacing: 16) {
            if kind == .deal {
                Picker("Deals view", selection: $dealsView) { Text("Board").tag("Board"); Text("Table").tag("Table") }
                    .pickerStyle(.segmented).frame(width: 160)
                Picker("Stage", selection: $stageFilter) {
                    Text("All stages").tag("All stages")
                    ForEach(DealStage.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }.frame(width: 230)
            }
            if kind == .task {
                Picker("Task view", selection: $taskFilter) {
                    ForEach(["Upcoming", "Overdue", "Completed"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).frame(width: 280)
                if taskFilter == "Upcoming" { Text("Includes tasks without dates").font(.caption).foregroundStyle(Design.secondaryText) }
            }
            Text("\(filtered.count) shown").font(.caption).foregroundStyle(Design.secondaryText)
            Spacer()
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Design.motion)) { inspectorVisible.toggle() }
            } label: { Label(inspectorVisible ? "Hide details" : "Show details", systemImage: "sidebar.right") }
                .buttonStyle(FlatButtonStyle()).disabled(selection == nil).help("Toggle detail inspector")
        }.padding(.horizontal, 24).padding(.bottom, 16)
    }
    @ViewBuilder private var mainContent: some View {
        if filtered.isEmpty {
            VStack {
                EmptyState(symbol: kind?.symbol ?? "tray", title: query.isEmpty ? "Make room for your next \(kind?.title.lowercased() ?? "record")" : "No matches", detail: query.isEmpty ? "Add a record to start. Your work stays on this Mac." : "Try a different search or change the filter.")
                if store.isEmpty { Button("Load sample data", action: loadSamples).buttonStyle(FlatButtonStyle()).padding(.bottom, 40) }
            }
        } else if kind == .deal && dealsView == "Board" {
            DealBoard(store: store, deals: filtered, selection: $selection, open: { selection = $0; inspectorVisible = true })
        } else {
            RecordTable(store: store, records: filtered, kind: kind ?? .contact, selection: $selection, edit: { r in editor = RecordData(r) }, delete: { deleteID = $0.id }).id(kind)
        }
    }
    private func newRecord() {
        guard canPresent else { return }
        editor = RecordData(kind: kind ?? .deal)
    }
    private func navigate(_ r: CRMRecord) {
        section = r.kind.plural
        query = ""; stageFilter = "All stages"
        if r.kind == .task { taskFilter = r.completed ? "Completed" : r.isOverdue ? "Overdue" : "Upcoming" }
        // Section changes clear selection; select on the next UI turn.
        Task { @MainActor in selection = r.id; inspectorVisible = true }
    }
    private func loadSamples() { do { try store.loadSamples() } catch { store.report(error) } }
    private func exportBackup() {
        guard canPresent else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a folder for your backup"
        panel.prompt = "Export Here"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let date = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let destination = folder.appendingPathComponent("LightCRM-\(date)-\(UUID().uuidString.prefix(6)).lightcrmbackup")
        Task { await store.export(to: destination) }
    }
    private func chooseRestore() {
        guard canPresent else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a .lightcrmbackup folder"
        panel.prompt = "Review Restore"; panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK { restoreURL = panel.url }
    }
}

struct CurrencyEditor: View {
    let store: CRMStore
    @Environment(\.dismiss) private var dismiss
    @State private var currency = "USD"
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Workspace currency").font(Design.heading)
            Text("All deal amounts use one currency. Changing this label does not convert existing amounts.").foregroundStyle(Design.secondaryText)
            Picker("Currency", selection: $currency) {
                ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { code in Text("\(code) — \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code) }
            }
            if let error { Text(error).foregroundStyle(Design.red).font(.caption) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save") { do { try store.setCurrency(currency); dismiss() } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 440).onAppear { currency = store.currency }
    }
}
