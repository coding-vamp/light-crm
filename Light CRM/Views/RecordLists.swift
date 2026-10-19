import SwiftUI

private struct RecordRow: Identifiable {
    let record: CRMRecord
    var id: UUID { record.id }
    var title: String { record.title }
    var client: String { record.kind == .task ? record.deal?.title ?? record.contact?.title ?? "Unlinked" : record.client }
    var status: String { record.kind == .deal ? record.stageRaw : record.kind == .task ? record.completed ? "Completed" : "Open" : record.email }
    var amount: Decimal { record.value }
    var date: Date { record.due?.date ?? .distantFuture }
}

struct RecordTable: View {
    let store: CRMStore
    let records: [CRMRecord]
    let kind: RecordKind
    @Binding var selection: UUID?
    let edit: (CRMRecord) -> Void
    let delete: (CRMRecord) -> Void
    @State private var sort = [KeyPathComparator(\RecordRow.title)]
    private var rows: [RecordRow] { records.map { RecordRow(record: $0) }.sorted(using: sort) }
    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sort) {
            TableColumn(kind == .deal ? "Project" : kind == .task ? "Task" : "Name", value: \.title) { row in
                HStack(spacing: 8) {
                    if kind == .task {
                        Button { store.toggle(row.record) } label: {
                            Image(systemName: row.record.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(row.record.completed ? Design.green : Design.secondaryText)
                        }.buttonStyle(.plain).accessibilityLabel(row.record.completed ? "Mark \(row.title) incomplete" : "Complete \(row.title)")
                    }
                    Text(row.title).font(Design.control).lineLimit(2)
                }.padding(.vertical, 7)
            }.width(min: 160, ideal: 240)
            if kind != .company {
                TableColumn(kind == .task ? "Linked to" : "Client", value: \.client) { row in
                    Text(row.client).foregroundStyle(Design.secondaryText).lineLimit(1)
                }.width(min: 100, ideal: 150)
            }
            if kind == .deal {
                TableColumn("Value (\(store.currency))", value: \.amount) { row in Text(store.money(row.amount)).monospacedDigit() }.width(min: 100, ideal: 120)
                TableColumn("Stage", value: \.status) { row in StageBadge(stage: row.record.stage) }.width(min: 130, ideal: 160)
            }
            if kind == .contact {
                TableColumn("Email", value: \.status) { row in Text(row.record.email.isEmpty ? "—" : row.record.email).lineLimit(1) }.width(min: 130, ideal: 200)
            }
            if kind == .company {
                TableColumn("Website") { row in Text(row.record.website.isEmpty ? "—" : row.record.website).foregroundStyle(Design.secondaryText) }
            }
            if kind == .task || kind == .deal {
                TableColumn(kind == .task ? "Due" : "Follow-up", value: \.date) { row in DueLabel(day: row.record.due, overdue: row.record.isOverdue) }.width(min: 110, ideal: 140)
            }
        }
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let record = store.record(id) {
                Button("Edit \(record.kind.title)") { edit(record) }
                if record.kind == .deal { stageMenu(record) }
                if record.kind == .task { Button(record.completed ? "Mark Incomplete" : "Complete Task") { store.toggle(record) } }
                Button("Delete…", role: .destructive) { delete(record) }
            }
        } primaryAction: { ids in if let id = ids.first, let r = store.record(id) { edit(r) } }
        .padding(.horizontal, 12)
        .onAppear { if kind == .task { sort = [KeyPathComparator(\RecordRow.date), KeyPathComparator(\RecordRow.title)] } }
    }
    private func stageMenu(_ record: CRMRecord) -> some View {
        Menu("Change Stage") { ForEach(DealStage.allCases) { stage in Button(stage.rawValue) { store.move(record, to: stage) } } }
    }
}

struct DealBoard: View {
    let store: CRMStore
    let deals: [CRMRecord]
    @Binding var selection: UUID?
    let open: (UUID) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(DealStage.allCases) { stage in
                    DealColumn(store: store, stage: stage, deals: deals.filter { $0.stage == stage }, selection: $selection, open: open)
                }
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}

private struct DealColumn: View {
    let store: CRMStore
    let stage: DealStage
    let deals: [CRMRecord]
    @Binding var selection: UUID?
    let open: (UUID) -> Void
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Rectangle().fill(Design.stageColor(stage)).frame(width: 4, height: 24)
                Text(stage.rawValue).font(Design.control)
                Spacer()
                Text("\(deals.count)").font(.system(size: 12, weight: .bold)).monospacedDigit()
            }
            Text(store.money(deals.reduce(Decimal.zero) { $0 + $1.value })).font(.system(size: 12)).monospacedDigit().foregroundStyle(Design.secondaryText)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(deals) { deal in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { selection = deal.id; open(deal.id) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(deal.title).font(Design.control).lineLimit(3).multilineTextAlignment(.leading)
                                    Text(deal.client).font(.system(size: 12)).foregroundStyle(Design.secondaryText).lineLimit(2)
                                    Text(store.money(deal.value)).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("\(deal.title), \(deal.client), \(store.money(deal.value)). Show details")
                            HStack {
                                DueLabel(day: deal.due, overdue: deal.isOverdue)
                                Spacer(minLength: 0)
                                Menu {
                                    ForEach(DealStage.allCases) { target in Button(target.rawValue) { store.move(deal, to: target) } }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
                                    .accessibilityLabel("Change stage for \(deal.title)")
                            }
                        }.padding(14).background(selection == deal.id ? Design.selection : Design.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selection == deal.id ? Design.blue : .clear, lineWidth: 2))
                            .draggable(deal.id.uuidString)
                    }
                    if deals.isEmpty {
                        Text("Drop a deal here").font(.system(size: 12)).foregroundStyle(Design.secondaryText)
                            .frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                }
            }
        }.padding(12).frame(width: 246).frame(maxHeight: .infinity)
            .background(targeted ? Design.selection : Design.muted, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Design.blue : .clear, lineWidth: 2))
            .dropDestination(for: String.self) { values, _ in
                guard !store.busy, let id = values.first.flatMap(UUID.init(uuidString:)), let record = store.record(id), record.kind == .deal else { return false }
                store.move(record, to: stage); return true
            } isTargeted: { targeted = $0 }
    }
}
