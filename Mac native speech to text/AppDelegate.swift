//
//  AppDelegate.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var hotkeyMonitor: HotkeyMonitor?
    private var overlayController: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor?.stop()
        appState.stopListening()
    }
}
