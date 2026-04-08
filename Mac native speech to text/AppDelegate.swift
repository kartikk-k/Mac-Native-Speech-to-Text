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
    private var hotkeyMonitor: HotkeyMonitor?
    private var overlayController: OverlayWindowController?
    private var onboardingController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.permissionManager = permissionManager

        overlayController = OverlayWindowController(appState: appState)
        onboardingController = OnboardingWindowController(permissionManager: permissionManager)

        appState.onHide = { [weak self] in
            self?.overlayController?.hideImmediately()
        }

        appState.onShowOnboarding = { [weak self] in
            self?.showOnboarding()
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
                    self.appState.stopListening()
                }
            }
        )
        hotkeyMonitor?.start()

        // Show onboarding if permissions are missing
        if !permissionManager.allPermissionsGranted {
            showOnboarding()
        }
    }

    func showOnboarding() {
        onboardingController?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor?.stop()
        appState.cancelListening()
    }
}
