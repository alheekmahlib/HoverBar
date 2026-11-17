import Foundation
import os

/// Central logger with per-category streams (PLAN §4 — Support/Logger).
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.hawazensameer.hoverbar"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let control = Logger(subsystem: subsystem, category: "control")
    static let reveal = Logger(subsystem: subsystem, category: "reveal")
}
