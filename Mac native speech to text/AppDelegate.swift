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
    let permissionManager = PermissionManager()
    let usageTracker = UsageTracker()
    let snippetManager = SnippetManager()
    let updaterManager = UpdaterManager()
    private var hotkeyMonitor: HotkeyMonitor?
    private var overlayController: OverlayWindowController?
    private var onboardingController: OnboardingWindowController?
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.permissionManager = permissionManager
        appState.usageTracker = usageTracker
        appState.snippetManager = snippetManager

        overlayController = OverlayWindowController(appState: appState)
        onboardingController = OnboardingWindowController(permissionManager: permissionManager)
        mainWindowController = MainWindowController(usageTracker: usageTracker, permissionManager: permissionManager, snippetManager: snippetManager, appState: appState, updaterManager: updaterManager)

        appState.onHide = { [weak self] in
            self?.hotkeyMonitor?.isHandsFree = false
            self?.appState.isHandsFree = false
            self?.overlayController?.hideImmediately()
        }

        appState.onShowOnboarding = { [weak self] in
            self?.showOnboarding()
        }

        appState.onShowMainWindow = { [weak self] in
            self?.showMainWindow()
        }

        hotkeyMonitor = HotkeyMonitor(
            onHotkeyDown: { [weak self] in
                self?.appState.startListening()
                self?.overlayController?.show()
            },
            onHotkeyUp: { [weak self] in
                guard let self = self else { return }
                if self.appState.phase == .permissionDenied {
                    self.overlayController?.hideAfterDelay()
                } else {
                    self.appState.lastEndReason = .released
                    self.appState.stopListening()
                }
            },
            onHandsFreeToggle: { [weak self] in
                guard let self = self else { return }
                self.toggleHandsFree()
            },
            onCancel: { [weak self] in
                self?.appState.cancelListening()
            }
        )
        hotkeyMonitor?.start()

        // Show main window on launch (permission setup is embedded in the main window)
        showMainWindow()
    }

    private func toggleHandsFree() {
        if hotkeyMonitor?.isHandsFree == true {
            // Turn off hands-free: stop listening and process
            print("[AppDelegate] Hands-free OFF")
            hotkeyMonitor?.isHandsFree = false
            appState.isHandsFree = false
            appState.lastEndReason = .handsFreeStop
            appState.stopListening()
        } else {
            // Turn on hands-free: keep current session running (if already listening)
            print("[AppDelegate] Hands-free ON")
            hotkeyMonitor?.isHandsFree = true
            appState.isHandsFree = true
            if appState.phase != .listening {
                // Only start a new session if not already recording
                appState.startListening()
                overlayController?.show()
            }
        }
    }

    func showOnboarding() {
        onboardingController?.show()
    }

    func showMainWindow() {
        mainWindowController?.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor?.stop()
        appState.cancelListening()
    }
}
