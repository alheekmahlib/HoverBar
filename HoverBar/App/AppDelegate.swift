import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("HoverBar launched (phase 0 scaffold)")
    }
}
