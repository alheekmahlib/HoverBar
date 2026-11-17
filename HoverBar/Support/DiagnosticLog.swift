import Foundation

/// File-based diagnostic log (~/Library/Logs/HoverBar.log).
///
/// The unified log is hard to read from some environments, and Phase 4 needs a
/// "Copy diagnostics" feature anyway — a plain file covers both.
enum DiagnosticLog {
    static var path: String {
        NSHomeDirectory() + "/Library/Logs/HoverBar.log"
    }

    static func write(_ line: String) {
        let formatter = ISO8601DateFormatter()
        let text = "\(formatter.string(from: Date())) \(line)\n"
        let url = URL(fileURLWithPath: path)
        if let data = text.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
