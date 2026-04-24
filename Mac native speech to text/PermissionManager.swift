//
//  PermissionManager.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation
import AVFoundation
import Speech
import Cocoa

@Observable
class PermissionManager {
    var microphoneGranted = false
    var speechRecognitionGranted = false
    var accessibilityGranted = false

    var allPermissionsGranted: Bool {
        microphoneGranted && speechRecognitionGranted && accessibilityGranted
    }

    @ObservationIgnored
    private var accessibilityTimer: Timer?

    init() {
        checkAll()
    }

    func checkAll() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechRecognitionGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        // Use kAXTrustedCheckOptionPrompt=false to query without prompting
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphoneGranted = granted
                }
            }
        } else if status == .denied || status == .restricted {
            openSystemSettings("Privacy_Microphone")
        }
    }

    func requestSpeechRecognition() {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    self?.speechRecognitionGranted = newStatus == .authorized
                }
            }
        } else if status == .denied || status == .restricted {
            openSystemSettings("Privacy_SpeechRecognition")
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        startPollingAccessibility()
    }

    func startPollingAccessibility() {
        stopPollingAccessibility()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            DispatchQueue.main.async {
                self?.accessibilityGranted = trusted
            }
        }
    }

    func stopPollingAccessibility() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
