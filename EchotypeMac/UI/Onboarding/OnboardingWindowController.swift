//
//  OnboardingWindowController.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Cocoa
import SwiftUI

class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let permissionManager: PermissionManager
    private let appState: AppState
    /// Called when onboarding finishes (or is skipped/closed).
    var onFinished: (() -> Void)?

    init(permissionManager: PermissionManager, appState: AppState) {
        self.permissionManager = permissionManager
        self.appState = appState
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
        onFinished?()
    }

    func show() {
        NSApp.setActivationPolicy(.regular)

        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView(onDone: { [weak self] in
            self?.close()
        })
        .environment(permissionManager)
        .environmentObject(appState)

        let hostingView = NSHostingView(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = "Welcome to Echotype"
        // Let the SwiftUI .ultraThickMaterial background read as a real translucent
        // material (matching the main app) rather than sitting over an opaque fill.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    /// Finish onboarding (called from the view's Done/Skip). Fires onFinished via
    /// windowWillClose.
    func close() {
        window?.close()
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
