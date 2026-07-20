//
//  VolumeManager.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import CoreAudio
import AudioToolbox

final class VolumeManager {
    static let shared = VolumeManager()

    private var savedVolume: Float32?
    private var isMuted = false

    private init() {}

    /// Save current system volume and mute output.
    func muteSystem() {
        guard !isMuted else { return }

        guard let deviceID = defaultOutputDevice() else {
            print("[VolumeManager] no default output device")
            return
        }

        if let vol = getVolume(device: deviceID) {
            savedVolume = vol
            print("[VolumeManager] saved volume: \(vol)")
        }

        setMute(device: deviceID, muted: true)
        isMuted = true
        print("[VolumeManager] muted system audio")
    }

    /// Restore system volume to what it was before muting.
    func restoreSystem() {
        guard isMuted else { return }

        guard let deviceID = defaultOutputDevice() else {
            print("[VolumeManager] no default output device")
            return
        }

        setMute(device: deviceID, muted: false)

        if let vol = savedVolume {
            setVolume(device: deviceID, volume: vol)
            print("[VolumeManager] restored volume: \(vol)")
        }

        savedVolume = nil
        isMuted = false
        print("[VolumeManager] unmuted system audio")
    }

    // MARK: - CoreAudio helpers

    private func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    private func getVolume(device: AudioDeviceID) -> Float32? {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    private func setVolume(device: AudioDeviceID, volume: Float32) {
        var vol = volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
    }

    private func setMute(device: AudioDeviceID, muted: Bool) {
        var mute: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
    }
}
