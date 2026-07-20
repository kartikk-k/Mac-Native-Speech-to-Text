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

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.appState)
                .environment(appDelegate.permissionManager)
        } label: {
            Image(systemName: "microphone.fill")
        }
    }
}
