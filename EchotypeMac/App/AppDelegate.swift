//
//  AppDelegate.swift
//  Echotype Mac
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
    let failedStore = FailedTranscriptionStore()
    let historyStore = HistoryStore()
    private var hotkeyMonitor: HotkeyMonitor?
    private var overlayController: OverlayWindowController?
    private var onboardingController: OnboardingWindowController?
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.permissionManager = permissionManager
        appState.usageTracker = usageTracker
        appState.snippetManager = snippetManager
        appState.failedStore = failedStore
        appState.historyStore = historyStore

        overlayController = OverlayWindowController(appState: appState)
        onboardingController = OnboardingWindowController(permissionManager: permissionManager, appState: appState)
        onboardingController?.onFinished = { [weak self] in
            self?.showMainWindow()
        }
        mainWindowController = MainWindowController(usageTracker: usageTracker, permissionManager: permissionManager, snippetManager: snippetManager, appState: appState, updaterManager: updaterManager, failedStore: failedStore, historyStore: historyStore)

        appState.onHide = { [weak self] in
            self?.hotkeyMonitor?.isHandsFree = false
            self?.appState.isHandsFree = false
            self?.overlayController?.hideImmediately()
        }

        appState.onShow = { [weak self] in
            self?.overlayController?.show()
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

        // First run → onboarding (resumes at the last reached step). Otherwise the
        // main window. Onboarding's onFinished shows the main window afterward.
        if TranscriptionSettings.hasCompletedOnboarding {
            showMainWindow()
        } else {
            showOnboarding()
        }
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
