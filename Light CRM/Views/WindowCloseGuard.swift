import SwiftUI
import AppKit

/// SwiftUI owns the window delegate. Forward its behavior while intercepting only
/// closure, so a cancelled quit never strands an unsaved editor without a window.
struct WindowCloseGuard: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.original = window.delegate
            window.delegate = context.coordinator
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { }
    final class Coordinator: NSObject, NSWindowDelegate {
        var original: NSWindowDelegate?
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? { original }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard EditSession.confirmClose() else { return false }
            return original?.windowShouldClose?(sender) ?? true
        }
    }
}

extension EditSession {
    static func confirmClose() -> Bool {
        if busy {
            let alert = NSAlert(); alert.messageText = "A file operation is still running"
            alert.informativeText = "Wait for it to finish before closing Light CRM."; alert.runModal()
            return false
        }
        guard hasChanges else { return true }
        let alert = NSAlert(); alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "Your changes in the editor have not been saved."
        alert.addButton(withTitle: "Keep Editing"); alert.addButton(withTitle: "Discard Changes")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        hasChanges = false
        return true
    }
}
