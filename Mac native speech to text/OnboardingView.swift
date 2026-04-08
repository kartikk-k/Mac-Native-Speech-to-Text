//
//  OnboardingView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(PermissionManager.self) var permissionManager
    var onDone: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "mic.badge.waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Mac Native Speech to Text")
                    .font(.system(size: 20, weight: .semibold))

                Text("Grant the following permissions to get started.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Permission rows
            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    iconColor: .orange,
                    title: "Microphone",
                    description: "Record your voice for transcription.",
                    granted: permissionManager.microphoneGranted,
                    action: { permissionManager.requestMicrophone() }
                )

                permissionRow(
                    icon: "waveform",
                    iconColor: .blue,
                    title: "Speech Recognition",
                    description: "Convert speech to text on-device.",
                    granted: permissionManager.speechRecognitionGranted,
                    action: { permissionManager.requestSpeechRecognition() }
                )

                permissionRow(
                    icon: "lock.shield",
                    iconColor: .green,
                    title: "Accessibility",
                    description: "Insert text and detect keyboard shortcuts.",
                    granted: permissionManager.accessibilityGranted,
                    action: { permissionManager.requestAccessibility() }
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Done button
            Button(action: {
                permissionManager.checkAll()
                if permissionManager.allPermissionsGranted {
                    onDone?()
                }
            }) {
                Text("Continue")
                    .foregroundStyle(Color.white)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor)
            )
            .opacity(permissionManager.allPermissionsGranted ? 1 : 0.5)
            .disabled(!permissionManager.allPermissionsGranted)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 420)
        .onAppear {
            permissionManager.checkAll()
            permissionManager.startPollingAccessibility()
        }
        .onDisappear {
            permissionManager.stopPollingAccessibility()
        }
    }

    @ViewBuilder
    private func permissionRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color.white.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity((0.2)))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThickMaterial)
        )
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environment(PermissionManager())
}
