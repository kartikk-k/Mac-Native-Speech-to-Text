# Echotype Mac

Dictate anywhere on your Mac. Hold a key, speak, release — Echotype types it into
whatever app you're in. Free and open source.

- **On-device by default** — transcribe for free and private using Apple's built-in
  speech recognition. No account, no setup.
- **Or bring your own OpenAI key** for faster, more accurate transcription
  (`gpt-realtime-whisper`, streamed live).
- **Grammar & rephrase cleanup** — optionally fix grammar and polish phrasing as you
  dictate.
- **Works everywhere** — the text is inserted at your cursor in any app.
- **History** — your last 100 transcriptions, with audio playback and re-transcribe.

## Shortcuts

Echotype uses the **Globe (Fn)** key. (On first launch it disables the Globe key's
emoji-picker so the key is free for dictation — the emoji picker can be restored in
System Settings → Keyboard.)

| Action | Shortcut |
| --- | --- |
| **Dictate (hold-to-talk)** | Hold **Globe (Fn)**, speak, release |
| **Start hands-free** | **Double-press Globe**, then let go and keep talking |
| **Start hands-free while holding** | Press **Space** while holding Globe (then release Globe) |
| **Stop hands-free** | Press **Globe once** (or **Esc**) |
| **Cancel a recording** | **Delete / Backspace** while recording |

You can also set a **custom hotkey** in Settings if your keyboard has no Globe/Fn key.

## Requirements

- macOS 14+
- Permissions: **Microphone**, **Speech Recognition**, and **Accessibility** (Echotype
  walks you through granting these on first run).

## Install

Download the latest `.dmg` from
[Releases](https://github.com/kartikk-k/Echotype-Mac/releases), open it, and drag
**Echotype Mac** to Applications. The app is signed and notarized. Auto-updates are
delivered via Sparkle.

## Building from source

Open ` Echotype Mac.xcodeproj` in Xcode and build the **Echotype Mac** scheme, or use the
release script:

```bash
./scripts/build-dmg.sh          # builds a universal, Developer-ID-signed .dmg
# then notarize + staple (see the script's printed instructions)
```

## Privacy

- **Built-in engine:** audio is transcribed on-device; nothing leaves your Mac.
- **OpenAI engine:** your speech is sent to OpenAI for transcription; only the resulting
  text is returned. Your API key is stored in your Keychain.

## License

Open source. See the repository for details.
