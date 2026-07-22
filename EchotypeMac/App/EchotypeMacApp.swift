//
//  EchotypeMacApp.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

@main
struct EchotypeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Mirror of TranscriptionSettings.showMenuBarIcon so the menu bar item can be
    // shown/hidden live from Settings (default ON).
    @AppStorage("setting_showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarMenu()
                .environmentObject(appDelegate.appState)
                .environment(appDelegate.permissionManager)
                .environmentObject(appDelegate.historyStore)
        } label: {
            Image(systemName: "microphone.fill")
        }
    }
}
