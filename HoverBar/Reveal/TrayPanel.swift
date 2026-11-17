import AppKit

/// The floating mini-dock tray shown below the menu bar (Sunrise identity:
/// warm glass pill). MVP behavior: no animation, appears on reveal, dismisses
/// on collapse; icons are clickable.
final class TrayPanel: NSPanel {
    struct Entry {
        let image: NSImage?
        let title: String
        let handler: () -> Void
    }

    private var handlers: [() -> Void] = []

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
    }

    /// Shows the tray below the given menu bar rectangle (AppKit coordinates),
    /// right-aligned like a system dropdown.
    func present(entries: [Entry], belowBar barRect: CGRect) {
        handlers = entries.map(\.handler)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10

        for (index, entry) in entries.enumerated() {
            stack.addArrangedSubview(makeButton(for: entry, index: index))
        }

        let pill = NSVisualEffectView()
        pill.material = .hudWindow
        pill.blendingMode = .behindWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 15
        pill.layer?.masksToBounds = true

        let padding: CGFloat = 9
        pill.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -padding),
            stack.topAnchor.constraint(equalTo: pill.topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -padding),
        ])

        let content = NSView()
        content.wantsLayer = true
        contentView = content
        content.addSubview(pill)
        pill.translatesAutoresizingMaskIntoConstraints = false

        let iconSize: CGFloat = 24
        let buttonExtent = iconSize + 8
        let width = CGFloat(entries.count) * buttonExtent + CGFloat(max(entries.count - 1, 0)) * 10 + padding * 2
        let height = buttonExtent + padding * 2
        let frame = NSRect(
            x: barRect.maxX - width - 8,
            y: barRect.minY - height - 2,
            width: width,
            height: height
        )
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pill.topAnchor.constraint(equalTo: content.topAnchor),
            pill.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        setContentSize(frame.size)
        setFrameOrigin(frame.origin)

        orderFrontRegardless()
        Log.reveal.info("tray presented with \(entries.count, privacy: .public) entries")
    }

    func dismiss() {
        orderOut(nil)
        handlers.removeAll()
    }

    private func makeButton(for entry: Entry, index: Int) -> NSView {
        let button: NSButton
        if let original = entry.image, let image = original.copy() as? NSImage {
            image.size = NSSize(width: 24, height: 24)
            button = NSButton(image: image, target: self, action: #selector(entryClicked(_:)))
            button.imageScaling = .scaleProportionallyDown
        } else {
            button = NSButton(title: entry.title, target: self, action: #selector(entryClicked(_:)))
            button.font = .systemFont(ofSize: 11, weight: .medium)
        }
        button.tag = index
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = entry.title
        button.setButtonType(.momentaryChange)
        return button
    }

    @objc private func entryClicked(_ sender: NSButton) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }
}
