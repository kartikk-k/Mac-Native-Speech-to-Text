//
//  AudioPreviewPlayer.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Small shared player for previewing recorded clips (in History). Observable so
//  views can show a Play / Pause toggle and know which clip is playing. One clip
//  plays at a time.
//

import Foundation
import AVFoundation
import Combine

final class AudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPreviewPlayer()

    /// URL of the clip currently loaded, and whether it's actively playing.
    @Published private(set) var currentURL: URL?
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?

    /// True when `url` is the loaded clip AND it's playing right now.
    func isPlaying(_ url: URL) -> Bool { isPlaying && currentURL == url }

    /// Toggle playback for `url`: start it, pause if it's the playing clip, or
    /// resume if it's paused.
    func toggle(url: URL) {
        if currentURL == url, let player = player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }
        // Different clip (or nothing loaded) — start fresh.
        player?.stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        player = p
        currentURL = url
        p.play()
        isPlaying = true
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentURL = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentURL = nil
    }
}
