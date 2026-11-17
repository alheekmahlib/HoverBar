import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.hawazensameer.hoverbar"

    static let app = Logger(subsystem: subsystem, category: "app")
}
