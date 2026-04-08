//
//  HotkeyMonitor.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Cocoa
import Carbon.HIToolbox

class HotkeyMonitor {
    private var flagsMonitor: Any?
    private var isHotkeyHeld = false
    private let onHotkeyDown: () -> Void
    private let onHotkeyUp: () -> Void

    // Ctrl + Option
    private let requiredFlags: NSEvent.ModifierFlags = [.control, .option]

    init(onHotkeyDown: @escaping () -> Void, onHotkeyUp: @escaping () -> Void) {
        self.onHotkeyDown = onHotkeyDown
        self.onHotkeyUp = onHotkeyUp
    }

    func start() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    func stop() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let bothHeld = flags.contains(requiredFlags)

        if bothHeld && !isHotkeyHeld {
            isHotkeyHeld = true
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyDown()
            }
        } else if !bothHeld && isHotkeyHeld {
            isHotkeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyUp()
            }
        }
    }

    deinit {
        stop()
    }
}
