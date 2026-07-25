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
            // Swallow Escape key-up while hands-free so it doesn't leak.
            if isHandsFree && keyCode == HotkeyMonitor.escapeKeyCode {
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

            // Delete/Backspace → cancel only if actively recording.
            if keyCode == HotkeyMonitor.deleteKeyCode && (isHotkeyHeld || isHandsFree) {
                print("[HotkeyMonitor] >>> CANCEL (Delete)")
                isHotkeyHeld = false
                isHandsFree = false
                DispatchQueue.main.async { [weak self] in self?.onCancel() }
                return nil
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

    private static let doubleTapWindow: CFTimeInterval = 0.3
    private var lastFnUpTime: CFTimeInterval = 0
    private var fnDownTime: CFTimeInterval = 0
    private var pendingTapWork: DispatchWorkItem?

    private func handleFnDown() {
        fnIsDown = true
        let now = CFAbsoluteTimeGetCurrent()

        // A second press soon after the last release = double-tap → hands-free.
        if now - lastFnUpTime < HotkeyMonitor.doubleTapWindow {
            // Cancel the pending "transcribe the first tap" work — instead of
            // transcribing that brief first tap, we roll its recording straight
            // into hands-free mode (no cancel/flicker: toggleHandsFree ON keeps an
            // already-running session).
            pendingTapWork?.cancel(); pendingTapWork = nil
            isHotkeyHeld = false  // the hold is over; hands-free owns the session now
            print("[HotkeyMonitor] >>> double-tap Globe — hands-free toggle")
            DispatchQueue.main.async { [weak self] in self?.onHandsFreeToggle() }
            lastFnUpTime = 0
            return
        }

        // In hands-free mode, a fresh single press stops it.
        if isHandsFree {
            print("[HotkeyMonitor] >>> Globe press — hands-free OFF")
            DispatchQueue.main.async { [weak self] in self?.onHandsFreeToggle() }
            return
        }

        // Normal hold-to-talk: start recording now.
        fnDownTime = now
        isHotkeyHeld = true
        print("[HotkeyMonitor] >>> Globe DOWN (recording)")
        DispatchQueue.main.async { [weak self] in self?.onHotkeyDown() }
    }

    private func handleFnUp() {
        fnIsDown = false
        lastFnUpTime = CFAbsoluteTimeGetCurrent()

        guard isHotkeyHeld else { return }  // e.g. release after a mode toggle
        let heldFor = CFAbsoluteTimeGetCurrent() - fnDownTime

        if heldFor >= HotkeyMonitor.doubleTapWindow {
            // Clearly a hold → transcribe immediately on release.
            isHotkeyHeld = false
            print("[HotkeyMonitor] <<< Globe UP (transcribe)")
            DispatchQueue.main.async { [weak self] in self?.onHotkeyUp() }
        } else {
            // Short tap — could be the first half of a double-tap. Defer the
            // transcribe briefly; a second press (handleFnDown) will cancel this.
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.isHotkeyHeld else { return }
                self.isHotkeyHeld = false
                print("[HotkeyMonitor] <<< Globe tap (transcribe)")
                DispatchQueue.main.async { self.onHotkeyUp() }
                self.pendingTapWork = nil
            }
            pendingTapWork = work
            DispatchQueue.global().asyncAfter(deadline: .now() + HotkeyMonitor.doubleTapWindow, execute: work)
        }
    }

    deinit {
        stop()
    }
}
