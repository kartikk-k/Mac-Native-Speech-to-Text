//
//  MainWindowController.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Cocoa
import SwiftUI

class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let usageTracker: UsageTracker
    private let permissionManager: PermissionManager
    private let snippetManager: SnippetManager
    private let appState: AppState
    private let updaterManager: UpdaterManager

    init(usageTracker: UsageTracker, permissionManager: PermissionManager, snippetManager: SnippetManager, appState: AppState, updaterManager: UpdaterManager) {
        self.usageTracker = usageTracker
        self.permissionManager = permissionManager
        self.snippetManager = snippetManager
        self.appState = appState
        self.updaterManager = updaterManager
    }

    func show() {
        NSApp.setActivationPolicy(.regular)

        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let mainView = MainWindowView(updaterManager: updaterManager)
            .environment(usageTracker)
            .environment(permissionManager)
            .environment(snippetManager)
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: mainView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 800, height: 500)
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

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
