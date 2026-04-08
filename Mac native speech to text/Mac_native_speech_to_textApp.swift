//
//  Mac_native_speech_to_textApp.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

@main
struct Mac_native_speech_to_textApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.appState)
                .environment(appDelegate.permissionManager)
        } label: {
            Image(systemName: appDelegate.appState.phase == .hidden ? "mic" : "mic.fill")
        }
    }
}
