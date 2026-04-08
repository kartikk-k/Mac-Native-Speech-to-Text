//
//  MainWindowView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

// MARK: - Tab Model

enum MainTab: String, CaseIterable {
    case home = "Home"
    case stats = "Stats"
    case settings = "Settings"
    case invite = "Invite"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .stats: return "chart.bar.xaxis.ascending"
        case .settings: return "gearshape.fill"
        case .invite: return "person.badge.plus"
        }
    }
}

// MARK: - Main Window

struct MainWindowView: View {
    @Environment(PermissionManager.self) private var permissionManager
    @State private var selectedTab: MainTab = .home

    var body: some View {
        Group {
            if permissionManager.allPermissionsGranted {
                HStack(spacing: 0) {
                    SidebarView(selectedTab: $selectedTab)

                    Group {
                        switch selectedTab {
                        case .home:
                            HomeTabView()
                        case .stats:
                            StatsTabView()
                        case .settings:
                            SettingsTabView()
                        case .invite:
                            InviteTabView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                PermissionSetupView()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

// MARK: - Permission Setup (embedded in main window)

struct PermissionSetupView: View {
    @Environment(PermissionManager.self) private var permissionManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Mac Native Speech to Text")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Grant the following permissions to get started.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.bottom, 28)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Record your voice for transcription.",
                    granted: permissionManager.microphoneGranted,
                    action: { permissionManager.requestMicrophone() }
                )

                permissionRow(
                    icon: "waveform",
                    title: "Speech Recognition",
                    description: "Convert speech to text on-device.",
                    granted: permissionManager.speechRecognitionGranted,
                    action: { permissionManager.requestSpeechRecognition() }
                )

                permissionRow(
                    icon: "lock.shield",
                    title: "Accessibility",
                    description: "Insert text and detect keyboard shortcuts.",
                    granted: permissionManager.accessibilityGranted,
                    action: { permissionManager.requestAccessibility() }
                )
            }
            .frame(maxWidth: 420)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    MainWindowView()
        .environment(PermissionManager())
}
