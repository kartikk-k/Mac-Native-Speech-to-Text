//
//  HotkeyRecorderView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  A "click to record shortcut" control for the hold-to-record hotkey. Clicking
//  it enters capture mode; the next key press (with any modifiers) becomes the
//  binding. It also accepts the Fn/Globe key. Backed by an NSView so it can
//  intercept raw key events regardless of first responder chrome.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var binding: HotkeyBinding

    func makeNSView(context: Context) -> RecorderNSView {
        let v = RecorderNSView()
        v.onCapture = { self.binding = $0 }
        v.binding = binding
        return v
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.binding = binding
        nsView.needsDisplay = true
    }

    final class RecorderNSView: NSView {
        var binding: HotkeyBinding = .fn { didSet { rebuild() } }
        var onCapture: ((HotkeyBinding) -> Void)?
        private var recording = false
        private var monitor: Any?
        private let label = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 7
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
                heightAnchor.constraint(equalToConstant: 30),
            ])
            rebuild()
        }
        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            recording ? stopRecording(cancelled: true) : startRecording()
        }

        private func startRecording() {
            recording = true
            window?.makeFirstResponder(self)
            // Capture the next key/flags globally-to-this-app via a local monitor.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
                self?.handle(ev)
                return nil  // swallow so it doesn't act elsewhere
            }
            rebuild()
        }

        private func stopRecording(cancelled: Bool) {
            recording = false
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            rebuild()
        }

        private func handle(_ ev: NSEvent) {
            // Escape cancels capture.
            if ev.type == .keyDown && ev.keyCode == UInt16(kVK_Escape) {
                stopRecording(cancelled: true); return
            }
            // Fn/Globe pressed (flagsChanged carrying the function modifier).
            if ev.type == .flagsChanged {
                if ev.modifierFlags.contains(.function) {
                    commit(.fn)
                }
                return
            }
            // A regular key with whatever modifiers are held.
            if ev.type == .keyDown {
                var flags: CGEventFlags = []
                if ev.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
                if ev.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
                if ev.modifierFlags.contains(.shift) { flags.insert(.maskShift) }
                if ev.modifierFlags.contains(.control) { flags.insert(.maskControl) }
                commit(HotkeyBinding(isFn: false, keyCode: Int64(ev.keyCode), modifiers: flags))
            }
        }

        private func commit(_ b: HotkeyBinding) {
            binding = b
            onCapture?(b)
            stopRecording(cancelled: false)
        }

        private func rebuild() {
            if recording {
                label.stringValue = "Press a key…"
                label.textColor = NSColor.white.withAlphaComponent(0.9)
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
                layer?.borderWidth = 1
                layer?.borderColor = NSColor.controlAccentColor.cgColor
            } else {
                label.stringValue = binding.displayName
                label.textColor = NSColor.white.withAlphaComponent(0.85)
                layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
                layer?.borderWidth = 1
                layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            }
        }
    }
}
