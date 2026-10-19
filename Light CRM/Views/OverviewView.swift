import SwiftUI

struct OverviewView: View {
    let store: CRMStore
    let open: (CRMRecord) -> Void
    let add: () -> Void
    private var active: [CRMRecord] { store.all(.deal).filter { $0.stage.isActive } }
    private var tasks: [CRMRecord] { store.all(.task).filter { !$0.completed }.sorted { ($0.due?.date ?? .distantFuture) < ($1.due?.date ?? .distantFuture) } }
    private var followups: [CRMRecord] { active.filter { $0.due != nil }.sorted { $0.due! < $1.due! } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    metric("Open pipeline", value: store.money(active.reduce(0) { $0 + $1.value }), detail: store.currency, symbol: "chart.bar", color: Design.blue)
                    metric("Active deals", value: "\(active.count)", detail: "In your pipeline", symbol: "rectangle.3.group", color: Design.blue)
                    metric("Overdue tasks", value: "\(tasks.filter(\.isOverdue).count)", detail: "Need attention", symbol: "exclamationmark.circle", color: Design.red)
                    metric("Follow-ups today", value: "\(active.filter { $0.due == Day() }.count)", detail: "Keep things moving", symbol: "arrow.turn.up.right", color: Design.amber)
                }
                if store.isEmpty {
                    VStack(spacing: 16) {
                        EmptyState(symbol: "sun.max", title: "A lighter way to run your agency", detail: "Start with a client and a project. Keep every next step close to the work.")
                        HStack {
                            Button("Create your first deal", action: add).buttonStyle(FlatButtonStyle(primary: true))
                            Button("Load sample data") { do { try store.loadSamples() } catch { store.report(error) } }.buttonStyle(FlatButtonStyle())
                        }.padding(.bottom, 32)
                    }.frame(maxWidth: .infinity).background(Design.muted, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        workList("Your next steps", subtitle: "Incomplete tasks, earliest first", items: Array(tasks.prefix(8)), empty: "You’re all caught up. Add a task to plan your next step.")
                        workList("Client follow-ups", subtitle: "Open deals with a scheduled follow-up", items: Array(followups.prefix(8)), empty: "No follow-ups scheduled. Add a date to an active deal.")
                    }
                    HStack {
                        Image(systemName: "checkmark.shield").foregroundStyle(Design.green)
                        Text("Your workspace stays on this Mac. Export a backup regularly to keep another copy.").foregroundStyle(Design.secondaryText)
                    }.font(.system(size: 12)).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Design.muted, in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
    private func metric(_ title: String, value: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(Design.control).foregroundStyle(color)
            Text(value).font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text(detail).font(.system(size: 11)).foregroundStyle(Design.secondaryText)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Design.muted, in: RoundedRectangle(cornerRadius: 8))
    }
    private func workList(_ title: String, subtitle: String, items: [CRMRecord], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(Design.heading)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Design.secondaryText)
            if items.isEmpty { Text(empty).foregroundStyle(Design.secondaryText).padding(.vertical, 32) }
            ForEach(items) { r in
                HStack(alignment: .top, spacing: 12) {
                    if r.kind == .task {
                        Button { store.toggle(r) } label: { Image(systemName: "circle").font(.system(size: 19)) }.buttonStyle(.plain).accessibilityLabel("Complete \(r.title)")
                    } else { Image(systemName: "arrow.up.right").foregroundStyle(Design.blue) }
                    Button { open(r) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(r.title).font(Design.control).multilineTextAlignment(.leading)
                            Text(r.kind == .task ? r.deal?.title ?? r.contact?.title ?? "Unlinked task" : r.nextAction.isEmpty ? r.client : r.nextAction)
                                .font(.system(size: 12)).foregroundStyle(Design.secondaryText).lineLimit(2)
                            DueLabel(day: r.due, overdue: r.isOverdue)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.padding(14).background(Design.muted, in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
