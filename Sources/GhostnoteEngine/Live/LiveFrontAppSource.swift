import AppKit
import ApplicationServices

/// The live source: an NSWorkspace activation notification for the app, and an AXObserver on the front app for its window (G-14).
/// It runs on the main actor, because the notification and the observer's run loop source both deliver on the main run loop.
/// It never polls and never asks for the Accessibility grant, so without the grant it reports the app alone (G-08).
@MainActor
final class LiveFrontAppSource: FrontAppSource {
    private var continuation: AsyncStream<FrontReading>.Continuation?
    private(set) var activation: (any NSObjectProtocol)?
    private(set) var observer: AXObserver?
    private var observedPID: pid_t?

    nonisolated init() {}

    func readings() -> AsyncStream<FrontReading> {
        // A second call replaces the first, so one stream and one set of observers exist at a time.
        self.continuation?.onTermination = nil
        self.continuation?.finish()
        self.tearDown()

        let (stream, continuation) = AsyncStream<FrontReading>.makeStream()
        continuation.onTermination = { _ in
            Task { @MainActor in self.tearDown() }
        }
        self.continuation = continuation
        self.activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.frontChanged() }
        }
        self.frontChanged()
        return stream
    }

    /// Removes the activation observer and the AXObserver, which the engine's stop reaches through the end of the stream.
    func tearDown() {
        if let old = self.activation {
            NSWorkspace.shared.notificationCenter.removeObserver(old)
        }
        self.activation = nil
        if let old = self.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .defaultMode)
        }
        self.observer = nil
        self.observedPID = nil
    }

    /// Moves the AXObserver to the front app when the app changed or no observer exists, and reports a reading.
    func frontChanged() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return } // No app is in front, so nothing changed.
        if app.processIdentifier != self.observedPID || self.observer == nil {
            self.observe(pid: app.processIdentifier)
        }
        self.report()
    }

    func report() {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return } // No app scope to report.
        var reading = FrontReading(bundleID: bundleID, trusted: AXIsProcessTrusted())
        if reading.trusted, let window = LiveFrontAppSource.focusedWindow(pid: app.processIdentifier) {
            reading.document = LiveFrontAppSource.string(window, kAXDocumentAttribute)
            reading.url = LiveFrontAppSource.string(window, kAXURLAttribute)
            reading.title = LiveFrontAppSource.string(window, kAXTitleAttribute)
        }
        self.continuation?.yield(reading)
    }

    func observe(pid: pid_t) {
        if let old = self.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .defaultMode)
        }
        self.observer = nil
        self.observedPID = pid
        guard AXIsProcessTrusted() else { return } // Without the grant, the next activation tries again.

        var made: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let source = Unmanaged<LiveFrontAppSource>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { source.report() }
        }
        guard AXObserverCreate(pid, callback, &made) == .success, let made else { return }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXTitleChangedNotification] {
            AXObserverAddNotification(made, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .defaultMode)
        self.observer = made
    }
}

// MARK: - Accessibility reads

extension LiveFrontAppSource {
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let url = value as? URL {
            return url.absoluteString
        }
        return value as? String
    }
}
