//
//  HotkeyMonitor.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Cocoa
import Carbon.HIToolbox

class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    /// The event tap runs on its OWN dedicated thread with its own run loop, NOT
    /// the main run loop. A `.cgSessionEventTap` sits in the path of every system
    /// keystroke: whatever run loop services it must never stall, or ALL keyboard
    /// input across macOS freezes until the OS force-disables the tap. Keeping it
    /// off the main thread means nothing the app does (audio, network, SwiftUI,
    /// logging) can ever block global input.
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var isHotkeyHeld = false
    private var fnIsDown = false

    /// True while the custom (non-Fn) trigger key is held down.
    private var customKeyDown = false

    private let onHotkeyDown: () -> Void
    private let onHotkeyUp: () -> Void
    private let onHandsFreeToggle: () -> Void
    private let onCancel: () -> Void

    // Fn (Globe) key
    private static let fnKeyCode: Int64 = 63
    // Space key — only used to promote a hold into hands-free (see keyDown).
    private static let spaceKeyCode: Int64 = 49
    // Escape key
    private static let escapeKeyCode: Int64 = 53
    // Delete/Backspace key
    private static let deleteKeyCode: Int64 = 51

    /// Whether the event tap is active
    var isRunning: Bool { eventTap != nil }

    /// Whether hands-free mode is active. Written from the main thread (AppDelegate)
    /// and read from the tap thread inside `handleEvent`, so it's lock-guarded to
    /// avoid a cross-thread data race on the swallow logic.
    private let flagLock = NSLock()
    private var _isHandsFree = false
    var isHandsFree: Bool {
        get { flagLock.lock(); defer { flagLock.unlock() }; return _isHandsFree }
        set { flagLock.lock(); _isHandsFree = newValue; flagLock.unlock() }
    }

    /// The active hold-to-record binding, reloaded live from Settings. Read on the
    /// tap thread, written on main — lock-guarded.
    private var _binding: HotkeyBinding = TranscriptionSettings.hotkeyBinding
    private var binding: HotkeyBinding {
        get { flagLock.lock(); defer { flagLock.unlock() }; return _binding }
        set { flagLock.lock(); _binding = newValue; flagLock.unlock() }
    }

    init(
        onHotkeyDown: @escaping () -> Void,
        onHotkeyUp: @escaping () -> Void,
        onHandsFreeToggle: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onHotkeyDown = onHotkeyDown
        self.onHotkeyUp = onHotkeyUp
        self.onHandsFreeToggle = onHandsFreeToggle
        self.onCancel = onCancel

        // Reload the binding when the user changes it in Settings.
        NotificationCenter.default.addObserver(
            forName: TranscriptionSettings.hotkeyBindingChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.binding = TranscriptionSettings.hotkeyBinding
        }
    }

    /// Open System Settings to the Keyboard pane
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        if eventTap != nil || tapThread != nil { return }

        // Spin up a dedicated thread that owns the tap's run loop. See tapThread.
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            let installed = self.installTap()
            if installed {
                // Run this thread's run loop forever to service the tap.
                CFRunLoopRun()
            }
            // If install failed, the retry timer (scheduled on this run loop)
            // keeps the loop alive; run it so retries can fire.
            if !installed {
                CFRunLoopRun()
            }
        }
        thread.name = "com.echotype.hotkeytap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    /// Create + enable the tap on the CURRENT run loop (the tap thread). Returns
    /// false if creation failed (e.g. Accessibility not yet granted).
    private func installTap() -> Bool {
        // Listen for flagsChanged (Fn), keyDown, and keyUp
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyMonitor] Failed to create event tap — will retry when Accessibility is granted")
            startRetrying()
            return false
        }

        stopRetrying()
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[HotkeyMonitor] started on dedicated thread — Fn (hold) and Fn+Space (hands-free)")
        return true
    }

    func stop() {
        stopRetrying()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource, let loop = tapRunLoop {
                CFRunLoopRemoveSource(loop, source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
            print("[HotkeyMonitor] stopped")
        }
        // Wake the tap thread's run loop so it can exit.
        if let loop = tapRunLoop {
            CFRunLoopStop(loop)
        }
        tapRunLoop = nil
        tapThread = nil
    }

    // MARK: - Retry

    private func startRetrying() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if AXIsProcessTrusted() {
                print("[HotkeyMonitor] Accessibility now granted — retrying event tap")
                // We're already running on the tap thread's run loop; install
                // directly rather than spawning another thread.
                _ = self.installTap()
            }
        }
    }

    private func stopRetrying() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    // MARK: - Event handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if the system disabled our tap
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let activeBinding = binding

        // MARK: Key up
        if type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // Custom (non-Fn) hold key released → stop recording.
            if !activeBinding.isFn && keyCode == activeBinding.keyCode && customKeyDown {
                customKeyDown = false
                if isHotkeyHeld && !isHandsFree {
                    isHotkeyHeld = false
                    DispatchQueue.main.async { [weak self] in self?.onHotkeyUp() }
                }
                return nil
            }
            // Swallow the key-up for the Space/Escape we consumed on key-down so
            // they don't leak into the focused app.
            if isHandsFree && (keyCode == HotkeyMonitor.escapeKeyCode || keyCode == HotkeyMonitor.spaceKeyCode) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // MARK: Key down handling
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Custom (non-Fn) hold key pressed with the required modifiers → start
            // recording (mirrors Globe-down). Ignore auto-repeat while already held.
            if !activeBinding.isFn && keyCode == activeBinding.keyCode {
                let mods = event.flags.intersection(HotkeyBinding.relevantModifiers)
                if mods == activeBinding.modifiers.intersection(HotkeyBinding.relevantModifiers) {
                    if customKeyDown { return nil }  // swallow repeats
                    customKeyDown = true
                    if !isHandsFree {
                        isHotkeyHeld = true
                        DispatchQueue.main.async { [weak self] in self?.onHotkeyDown() }
                    }
                    return nil  // swallow so the key doesn't type
                }
            }

            // Space while ACTIVELY HOLDING to record → promote to hands-free, so
            // the user can release the key and keep talking (stop later with a
            // single Globe press). Space does nothing otherwise — it types
            // normally when not holding and never controls hands-free after this.
            if keyCode == HotkeyMonitor.spaceKeyCode && isHotkeyHeld && !isHandsFree {
                print("[HotkeyMonitor] >>> Space while holding — promote to hands-free")
                pendingTapWork?.cancel(); pendingTapWork = nil
                isHotkeyHeld = false  // hands-free owns the session now; Globe-up is a no-op
                DispatchQueue.main.async { [weak self] in self?.onHandsFreeToggle() }
                return nil  // swallow this one Space so it doesn't type
            }

            // Delete/Backspace while recording. A single press passes through as a
            // normal backspace (so the user can edit while dictating); only a
            // DOUBLE-press within the window requests a cancel. The recording is
            // NOT stopped here — AppState opens a short "Continue?" grace window.
            if keyCode == HotkeyMonitor.deleteKeyCode && (isHotkeyHeld || isHandsFree) {
                // Holding Delete to backspace many chars auto-repeats — never treat
                // a repeat as the second tap of the cancel gesture.
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if isRepeat { return Unmanaged.passUnretained(event) }

                let now = CFAbsoluteTimeGetCurrent()
                if awaitingSecondDelete && (now - lastDeleteDownTime) < HotkeyMonitor.deleteDoubleTapWindow {
                    // Second distinct press → cancel. Swallow this one so it doesn't
                    // also delete a character. Recording state is left intact so the
                    // user can still Continue.
                    awaitingSecondDelete = false
                    print("[HotkeyMonitor] >>> CANCEL requested (double Delete)")
                    DispatchQueue.main.async { [weak self] in self?.onCancel() }
                    return nil
                }
                // First press → arm the window and let it type (normal backspace).
                awaitingSecondDelete = true
                lastDeleteDownTime = now
                return Unmanaged.passUnretained(event)
            }

            // In hands-free mode, Escape stops it (Space is no longer used).
            if isHandsFree && keyCode == HotkeyMonitor.escapeKeyCode {
                print("[HotkeyMonitor] >>> hands-free OFF (Escape)")
                DispatchQueue.main.async { [weak self] in self?.onHandsFreeToggle() }
                return nil
            }

            return Unmanaged.passUnretained(event)
        }

        // MARK: Globe/Fn key (flagsChanged) — only when the binding IS Fn.
        guard type == .flagsChanged, activeBinding.isFn else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == HotkeyMonitor.fnKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let fnHeld = event.flags.contains(.maskSecondaryFn)

        if fnHeld && !fnIsDown {
            handleFnDown()
        } else if !fnHeld && fnIsDown {
            handleFnUp()
        }
        return nil  // always swallow Globe so it never leaks / opens the picker
    }

    // MARK: - Globe gesture state machine
    //
    // Hold Globe          → record while held (down starts, up transcribes).
    // Double-press Globe  → toggle hands-free ON.
    // Single press Globe  → while hands-free, toggle it OFF.
    //
    // Timings (on the tap thread): a press within `doubleTapWindow` of the last
    // release counts as a double-tap. A quick tap defers its "transcribe" briefly
    // so a second tap can upgrade it to a double-tap.

    /// Max gap between the two DOWN presses to count as a double-tap. Generous so
    /// a natural double-press is reliably caught.
    private static let doubleTapWindow: CFTimeInterval = 0.45
    /// A press held at least this long is unambiguously a "hold" (transcribe on
    /// release, no double-tap deferral).
    private static let holdThreshold: CFTimeInterval = 0.5
    private var lastFnDownTime: CFTimeInterval = 0
    private var fnDownTime: CFTimeInterval = 0
    private var pendingTapWork: DispatchWorkItem?
    /// A short first tap is pending confirmation as either a single tap
    /// (transcribe) or the first half of a double-tap (hands-free).
    private var awaitingSecondTap = false

    // MARK: - Delete double-tap (cancel)
    //
    // A SINGLE Delete now passes through as a normal backspace so the user can
    // edit text while dictating (hands-free). Only a DOUBLE-press of Delete —
    // two distinct presses within `deleteDoubleTapWindow` — requests a cancel,
    // mirroring the double-Globe gesture. Tap-thread state, no locking needed.
    private static let deleteDoubleTapWindow: CFTimeInterval = 0.4
    private var lastDeleteDownTime: CFTimeInterval = 0
    private var awaitingSecondDelete = false

    private func handleFnDown() {
        fnIsDown = true
        let now = CFAbsoluteTimeGetCurrent()
        let sinceLastDown = now - lastFnDownTime
        lastFnDownTime = now
        fnDownTime = now
        log("Globe DOWN")

        // Second press within the window of the first press = DOUBLE-TAP → hands-free.
        if awaitingSecondTap && sinceLastDown < HotkeyMonitor.doubleTapWindow {
            awaitingSecondTap = false
            pendingTapWork?.cancel(); pendingTapWork = nil
            isHotkeyHeld = false  // hands-free owns the (already-running) session now
            log(">>> double-tap Globe — toggling hands-free")
            DispatchQueue.main.async { [weak self] in self?.onHandsFreeToggle() }
            return
        }

        // Single fresh press while hands-free → stop it.
        if isHandsFree {
            log(">>> Globe press — hands-free OFF")
            DispatchQueue.main.async { [weak self] in self?.onHandsFreeToggle() }
            return
        }

        // Normal press → start recording immediately (hold-to-talk).
        isHotkeyHeld = true
        DispatchQueue.main.async { [weak self] in self?.onHotkeyDown() }
    }

    private func handleFnUp() {
        fnIsDown = false
        log("Globe UP")

        guard isHotkeyHeld else { return }  // release after a mode toggle → ignore
        let heldFor = CFAbsoluteTimeGetCurrent() - fnDownTime

        if heldFor >= HotkeyMonitor.holdThreshold {
            // Clearly a hold → transcribe now.
            isHotkeyHeld = false
            awaitingSecondTap = false
            log("<<< hold released — transcribe")
            DispatchQueue.main.async { [weak self] in self?.onHotkeyUp() }
            return
        }

        // Short tap → wait briefly to see if a second press makes it a double-tap.
        // If not, transcribe this single tap.
        awaitingSecondTap = true
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.awaitingSecondTap, self.isHotkeyHeld else { return }
            self.awaitingSecondTap = false
            self.isHotkeyHeld = false
            self.log("<<< single tap — transcribe")
            DispatchQueue.main.async { self.onHotkeyUp() }
            self.pendingTapWork = nil
        }
        pendingTapWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + HotkeyMonitor.doubleTapWindow, execute: work)
    }

    private func log(_ msg: String) { AppLog.shared.log("Hotkey", msg) }

    deinit {
        stop()
    }
}
