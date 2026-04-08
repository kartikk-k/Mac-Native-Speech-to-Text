//
//  TextInserter.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation
import AppKit
import Carbon.HIToolbox

enum TextInserter {
    static func insert(_ text: String) {
        guard !text.isEmpty else {
            print("[TextInserter] called with empty text, returning")
            return
        }

        print("[TextInserter] inserting: \"\(text)\"")
        print("[TextInserter] Accessibility trusted: \(AXIsProcessTrusted())")

        // Try CGEvent paste first (needs Accessibility), fall back to AppleScript
        if AXIsProcessTrusted() {
            print("[TextInserter] using CGEvent method")
            insertViaCGEvent(text)
        } else {
            print("[TextInserter] no Accessibility — using AppleScript fallback")
            insertViaAppleScript(text)
        }
    }

    private static func insertViaCGEvent(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save previous clipboard
        let previousString = pasteboard.string(forType: .string)
        print("[TextInserter] saved previous clipboard: \(previousString != nil)")

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[TextInserter] placed text on clipboard")

        let source = CGEventSource(stateID: .privateState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            print("[TextInserter] ERROR: failed to create CGEvent")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        print("[TextInserter] Cmd+V posted via cghidEventTap")

        // Restore previous clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previous = previousString {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
                print("[TextInserter] restored previous clipboard")
            }
        }
    }

    private static func insertViaAppleScript(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save previous clipboard
        let previousString = pasteboard.string(forType: .string)

        // Set our text on clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Use AppleScript to tell System Events to keystroke Cmd+V
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)

        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if let error = error {
            print("[TextInserter] AppleScript error: \(error)")
        } else {
            print("[TextInserter] AppleScript Cmd+V sent")
        }

        // Restore previous clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previous = previousString {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
                print("[TextInserter] restored previous clipboard")
            }
        }
    }
}
