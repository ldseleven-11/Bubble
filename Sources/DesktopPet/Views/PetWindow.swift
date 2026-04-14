import AppKit

// MARK: - PetWindow
class PetWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = false
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
