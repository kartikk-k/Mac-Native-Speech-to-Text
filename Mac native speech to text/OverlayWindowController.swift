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
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 120)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = hostingView

        self.window = window
    }

    func show() {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let window = window, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func hide() {
        guard let window = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}
