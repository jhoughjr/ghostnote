import AppKit
import ApplicationServices
import os

/// The live source reads the app from an NSWorkspace activation notification and the window from an AXObserver on the front app (G-14).
/// It runs on the main actor, because the notification and the observer's run loop source both deliver on the main run loop.
/// It never polls and never asks for the Accessibility grant, so without the grant it reports the app alone (G-08).
@MainActor
final class LiveFrontAppSource: FrontAppSource {
    /// The log of the live source, for the early outs that a working Mac does not take.
    /// The AX callback reaches it with no actor, so it is nonisolated, and Logger is Sendable.
    nonisolated private static let logger = Logger(subsystem: "ghostnote", category: "live")

    private var continuation: AsyncStream<FrontReading>.Continuation?
    private var generation = 0
    private(set) var activation: (any NSObjectProtocol)?
    private(set) var observer: AXObserver?
    private var observedPID: pid_t?

    nonisolated init() {}

    func readings() -> AsyncStream<FrontReading> {
        // A second call replaces the first, so one stream and one set of observers exist at a time.
        self.continuation?.onTermination = nil
        self.continuation?.finish()
        self.tearDown()

        self.generation += 1
        let generation = self.generation
        let (stream, continuation) = AsyncStream<FrontReading>.makeStream()
        continuation.onTermination = { _ in
            Task { @MainActor in
                // A teardown that an older stream queued must leave the observers of a newer stream in place (A-2).
                if self.generation == generation {
                    self.tearDown()
                }
            }
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
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .commonModes)
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
        // An app with no bundle identifier has no app scope to report.
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return }
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
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .commonModes)
        }
        self.observer = nil
        self.observedPID = pid
        guard AXIsProcessTrusted() else { return } // Without the grant, the next activation tries again.

        var made: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else {
                LiveFrontAppSource.logger.error("An AX callback arrived with no reference to the live source.")
                return
            }
            let source = Unmanaged<LiveFrontAppSource>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { source.report() }
        }
        let created = AXObserverCreate(pid, callback, &made)
        guard created == .success, let made else {
            LiveFrontAppSource.logger.error("AXObserverCreate failed for pid \(pid) with AX error \(created.rawValue).")
            return
        }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = 0
        for name in [kAXFocusedWindowChangedNotification, kAXTitleChangedNotification] {
            let result = AXObserverAddNotification(made, element, name as CFString, refcon)
            guard result == .success else {
                LiveFrontAppSource.logger.notice("Pid \(pid) refused \(name, privacy: .public) with AX error \(result.rawValue).")
                continue
            }
            registered += 1
        }
        // An app that refuses one notification still gives the other, so one registration is enough (A-4).
        guard registered > 0 else {
            LiveFrontAppSource.logger.notice("Pid \(pid) refused every AX notification, so no observer is kept and the next activation tries again.")
            return
        }

        // The common modes deliver callbacks while the main run loop tracks a menu or a drag (A-5).
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .commonModes)
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
