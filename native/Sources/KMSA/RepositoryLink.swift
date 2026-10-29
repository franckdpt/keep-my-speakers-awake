import AppKit
import SwiftUI
import KMSACore

struct RepositoryLink: NSViewRepresentable {
    var openRepository: () -> Void = { NSWorkspace.shared.open(AppLinks.repository) }

    func makeNSView(context: Context) -> LinkButton {
        let button = LinkButton()
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: LinkButton, context: Context) {
        button.openRepository = openRepository
        button.toolTip = L10n.text(.githubRepository)
        button.setAccessibilityLabel(L10n.text(.githubRepository))
    }

    final class LinkButton: NSButton {
        var openRepository: () -> Void = {}
        private var hoverArea: NSTrackingArea?
        private var hovering = false

        init() {
            super.init(frame: .zero)
            title = "GitHub"
            font = .systemFont(ofSize: 11)
            image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .medium))
            imagePosition = .imageTrailing
            imageHugsTitle = true
            contentTintColor = .secondaryLabelColor
            isBordered = false
            bezelStyle = .inline
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(openLink)
            setAccessibilityRole(.link)
            attributedTitle = NSAttributedString(string: title, attributes: [
                .font: font!, .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

        @objc private func openLink() { openRepository() }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(visibleRect, cursor: .pointingHand)
        }

        override func updateTrackingAreas() {
            if let hoverArea { removeTrackingArea(hoverArea) }
            // Menu-bar panels can remain non-key while another app is active.
            // activeAlways supports enter/move events in that state; it does
            // not deliver cursorUpdate, so handle these events explicitly.
            let area = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverArea = area
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) { showHand() }
        override func mouseMoved(with event: NSEvent) { showHand() }
        override func cursorUpdate(with event: NSEvent) { showHand() }
        override func mouseExited(with event: NSEvent) { restoreCursor() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            if window == nil { restoreCursor() }
        }

        private func showHand() {
            hovering = true
            NSCursor.pointingHand.set()
        }

        private func restoreCursor() {
            guard hovering else { return }
            hovering = false
            NSCursor.arrow.set()
        }
    }

    static func runChecks() {
        _ = NSApplication.shared
        let savedCursor = NSCursor.current
        defer { savedCursor.set() }
        let suite = "fr.franckdupont.kmsa.link-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var connected = false
        let model = AppModel(defaults: defaults, readSessionAvailable: { true },
                             readRoute: { connected ? HAL.Route(device: 0, uid: "link-check", name: "Test", isJack: true, alive: true) : HAL.Route() },
                             readAudio: { _ in HAL.Activity(known: true, microphoneBusy: false, outputBusy: false) },
                             readOutputVolume: { _ in 0.25 }, readIdleSeconds: { 0 },
                             makePlayer: { _ in SilentCheckPlayer() })
        var clicks = 0
        let host = NSHostingView(rootView: ControlPanel(model: model, updater: UpdateModel.preview(available: false)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let panel = NSPanel(contentRect: host.frame, styleMask: .borderless,
                            backing: .buffered, defer: false)
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        func findLink(in view: NSView) -> LinkButton? {
            (view as? LinkButton) ?? view.subviews.lazy.compactMap { findLink(in: $0) }.first
        }
        guard let button = findLink(in: host) else { preconditionFailure("Panel must contain the native GitHub link") }
        for hasJack in [false, true, false] {
            connected = hasJack
            model.refresh()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            panel.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            for x in [2.0, button.bounds.midX, button.bounds.maxX - 2] {
                let point = button.convert(NSPoint(x: x, y: button.bounds.midY), to: host.superview)
                let hit = host.hitTest(point)
                if hit !== button {
                    fputs("GitHub hit failure: jack=\(hasJack), button=\(button.frame), host=\(host.frame), point=\(point), hit=\(String(describing: hit))\n", stderr)
                    exit(1)
                }
            }
        }
        let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        button.updateTrackingAreas()
        precondition(panel.acceptsMouseMovedEvents)
        precondition(button.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.mouseMoved) })
        let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: center,
                                          modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                          context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        button.mouseEntered(with: enter)
        precondition(NSCursor.current == .pointingHand)
        NSCursor.arrow.set() // Simulate a surrounding host resetting the cursor.
        let move = NSEvent.mouseEvent(with: .mouseMoved, location: center,
                                      modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                      context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
        button.mouseMoved(with: move)
        precondition(NSCursor.current == .pointingHand)
        button.mouseExited(with: enter)
        precondition(NSCursor.current == .arrow)
        button.openRepository = { clicks += 1 }
        button.performClick(nil)
        precondition(clicks == 1)
        button.mouseEntered(with: enter)
        panel.contentView = nil
        precondition(NSCursor.current == .arrow)
        print("GitHub link: full-panel text/arrow hit tests with/without jack, inactive-panel tracking, enter/move hand cursor, exit/removal reset and click action passed. Simulated events; no window shown or URL opened.")
    }
}
