import SwiftUI
import AppKit

@main struct MyApp: App {
    @State private var store: CRMStore?
    @State private var startupError: String?
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        do { _store = State(initialValue: try CRMStore()) }
        catch { _startupError = State(initialValue: error.localizedDescription) }
    }
    var body: some Scene {
        Window("Light CRM", id: "main") {
            Group {
                if let store { ContentView(store: store).background(WindowCloseGuard()) }
                else {
                    VStack(spacing: 20) {
                        EmptyState(symbol: "externaldrive.badge.exclamationmark", title: "Your workspace couldn’t open", detail: startupError ?? "Unknown storage error")
                        Text("No data has been reset. Check available disk space and Application Support permissions, then reopen Light CRM.").frame(maxWidth: 420)
                        Button("Quit Light CRM") { NSApplication.shared.terminate(nil) }.padding(.bottom, 30)
                    }.frame(width: 600, height: 400)
                }
            }
        }
        .defaultSize(width: 1260, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Record") { NotificationCenter.default.post(name: .crmNew, object: nil) }.keyboardShortcut("n")
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Current Section") { NotificationCenter.default.post(name: .crmFind, object: nil) }.keyboardShortcut("f")
            }
            CommandMenu("Workspace") {
                Button("Export Backup…") { NotificationCenter.default.post(name: .crmExport, object: nil) }
                Button("Restore Backup…") { NotificationCenter.default.post(name: .crmRestore, object: nil) }
                Divider()
                Button("Currency…") { NotificationCenter.default.post(name: .crmCurrency, object: nil) }
            }
        }
    }
}

extension Notification.Name {
    static let crmNew = Notification.Name("crm.new")
    static let crmFind = Notification.Name("crm.find")
    static let crmExport = Notification.Name("crm.export")
    static let crmRestore = Notification.Name("crm.restore")
    static let crmCurrency = Notification.Name("crm.currency")
}

@MainActor enum EditSession { static var hasChanges = false; static var busy = false }

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        EditSession.confirmClose() ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
