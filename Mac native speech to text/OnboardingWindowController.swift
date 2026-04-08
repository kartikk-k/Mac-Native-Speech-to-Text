//
//  OnboardingWindowController.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Cocoa
import SwiftUI

class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let permissionManager: PermissionManager

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
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

        let hostingView = NSHostingView(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac Native Speech to Text"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.close()
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
