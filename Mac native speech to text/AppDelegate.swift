//
//  AppDelegate.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var hotkeyMonitor: HotkeyMonitor?
    private var overlayController: OverlayWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching")

        // Check Accessibility permission — prompt if not granted
        let trusted = AXIsProcessTrusted()
        print("[AppDelegate] Accessibility trusted: \(trusted)")
        if !trusted {
            print("[AppDelegate] WARNING: Accessibility not granted — prompting user")
            // This opens System Settings and highlights the app for the user to toggle on
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        overlayController = OverlayWindowController(appState: appState)

        hotkeyMonitor = HotkeyMonitor(
            onHotkeyDown: { [weak self] in
                self?.appState.startListening()
                self?.overlayController?.show()
            },
            onHotkeyUp: { [weak self] in
                self?.appState.stopListening()
                self?.overlayController?.hideAfterDelay()
            }
        )
        hotkeyMonitor?.start()

        // Watch for cancel (X button pressed while listening)
        appState.$isListening
            .dropFirst()
            .sink { [weak self] isListening in
                if !isListening && (self?.appState.transcribedText.isEmpty ?? true) {
                    self?.overlayController?.hideImmediately()
                }
            }
            .store(in: &cancellables)

        print("[AppDelegate] setup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] applicationWillTerminate")
        hotkeyMonitor?.stop()
        appState.stopListening()
    }
}
