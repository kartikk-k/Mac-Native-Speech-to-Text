# Echotype Mac v1.2

**New**
- **Custom cleanup instructions** — Fix grammar and Rephrase each now have their own instructions field in Settings. Tell Echotype how to clean your text ("use British spelling", "keep my casual tone", "make it more concise") and it folds those preferences into the cleanup pass.
- **Auto-copy on process / re-transcribe** — Processing a cancelled recording (or re-transcribing) from History now copies the result to your clipboard and shows a "Copied" indicator, so the text you came back for is ready to paste.

**Fixed**
- **Rephrase reliability** — Rephrasing (and grammar+rephrase) would intermittently fail with a "network connection was lost" error on longer text. Cleanup now automatically retries once on that transient error, so it no longer surfaces to you.

**Changed**
- Grammar and Rephrase cleanup are both **off by default** for a clean out-of-the-box experience.
- Delete-to-cancel now requires a double-press, keeps your audio, and offers a Continue option.
