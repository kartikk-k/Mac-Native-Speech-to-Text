//
//  SystemKeyConfig.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Makes the Globe/Fn key usable as a plain hotkey by disabling macOS's built-in
//  "press Globe to show the Emoji & Symbols picker" behavior. That behavior is a
//  single system preference — `com.apple.HIToolbox` → `AppleFnUsageType`:
//     0 = Do Nothing   1 = Change input source   2 = Emoji picker   3 = Dictation
//
//  We set it to 0 so a bare Globe press does nothing at the OS level, leaving our
//  event tap free to use it for hold-to-talk / hands-free without the picker
//  popping up. The change applies LIVE (no logout) once TextInputMenuAgent — the
//  agent that owns this behavior — is nudged to re-read the preference.
//

import Foundation
import AppKit

enum SystemKeyConfig {

    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString

    /// Current AppleFnUsageType, or nil if unset.
    static var fnUsageType: Int? {
        CFPreferencesCopyAppValue(key, domain) as? Int
    }

    /// Disable the Globe-key emoji picker (set AppleFnUsageType = 0) and apply it
    /// live. Idempotent — does nothing if already 0.
    static func disableEmojiPicker() {
        guard fnUsageType != 0 else { return }
        CFPreferencesSetAppValue(key, 0 as CFNumber, domain)
        CFPreferencesAppSynchronize(domain)
        refreshInputAgent()
        print("[SystemKeyConfig] AppleFnUsageType set to 0 (emoji picker disabled)")
    }

    /// Restore emoji-picker behavior (AppleFnUsageType = 2). Not called anywhere
    /// automatically — kept for completeness/uninstall.
    static func restoreEmojiPicker() {
        CFPreferencesSetAppValue(key, 2 as CFNumber, domain)
        CFPreferencesAppSynchronize(domain)
        refreshInputAgent()
    }

    /// Nudge the agent that reads this preference so the change is live without a
    /// logout. TextInputMenuAgent relaunches on demand.
    private static func refreshInputAgent() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["TextInputMenuAgent"]
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        try? task.run()
    }
}
