//
//  OverlayWindowController.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Cocoa
import SwiftUI

class OverlayWindowController {
    private var window: NSWindow?
    private let appState: AppState
    private var hideWorkItem: DispatchWorkItem?

    init(appState: AppState) {
        self.appState = appState
        setupWindow()
    }

    private func setupWindow() {
        let overlayView = OverlayView()
            .environmentObject(appState)

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 44)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = hostingView

        // Allow the hosting view to size itself
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView?.superview ?? window.contentView {
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        }

        self.window = window
    }

    func show() {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let window = window, let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let dockHeight: CGFloat = screenFrame.height - screen.visibleFrame.height - (screen.visibleFrame.origin.y - screenFrame.origin.y)
        let windowSize = window.frame.size

        // Bottom center, just above the dock
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.origin.y + dockHeight + 64
        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 1
        }
    }

    func hideAfterDelay() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    func hideImmediately() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hide()
    }

    private func hide() {
        guard let window = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}
