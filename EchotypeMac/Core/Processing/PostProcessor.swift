//
//  PostProcessor.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/9/26.
//

import Foundation

/// System-level text post-processing that runs before user snippets.
/// Handles file tagging, symbol insertion, and other automatic corrections.
struct PostProcessor {

    // MARK: - File Tagging

    /// Common file extensions (lowercase). Used to detect filenames in transcribed text.
    private static let fileExtensions: Set<String> = [
        "html", "htm", "css", "scss", "sass", "less",
        "js", "jsx", "ts", "tsx", "mjs", "cjs",
        "json", "xml", "yaml", "yml", "toml",
        "py", "rb", "go", "rs", "swift", "kt", "java", "c", "cpp", "h", "hpp", "cs",
        "sh", "bash", "zsh", "fish",
        "md", "mdx", "txt", "csv", "log",
        "sql", "graphql", "gql",
        "png", "jpg", "jpeg", "gif", "svg", "ico", "webp",
        "mp3", "mp4", "wav", "mov",
        "pdf", "doc", "docx", "xls", "xlsx",
        "env", "gitignore", "dockerignore",
        "vue", "svelte", "astro",
        "lock", "config", "conf",
        "wasm", "woff", "woff2", "ttf", "eot",
        "dart", "lua", "r", "m", "mm", "pl",
    ]

    /// Matches "at sign <filename>" or "at <filename>" where filename has a recognized extension.
    /// The extension portion is lowercased in the output.
    ///
    /// Examples:
    ///   "check at sign index.HTML for errors"  →  "check @index.html for errors"
    ///   "look at index.tsx and fix it"          →  "look @index.tsx and fix it"
    ///   "meet me at the office"                 →  "meet me at the office"  (no change — "the" has no extension)
    private static func applyFileTags(_ text: String) -> String {
        // Pattern: "at sign" or "at" followed by a filename with a dot + known extension.
        // The filename is captured as alphanumerics/hyphens/underscores + dot + extension.
        // Trailing punctuation (comma, period, etc.) is NOT captured.
        let extensionPattern = fileExtensions.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // Branch 1: "at sign <filename>"   Branch 2: "at <filename>"
        let pattern = #"(?i)\bat\s+sign\s+([\w\-]+\.(?:"# + extensionPattern + #"))\b|(?i)\bat\s+([\w\-]+\.(?:"# + extensionPattern + #"))\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var result = text
        // Process matches in reverse order so replacement indices stay valid
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

        for match in matches.reversed() {
            let fullRange = Range(match.range, in: result)!

            // Group 1 = filename after "at sign", Group 2 = filename after "at"
            let filename: String
            if let range1 = Range(match.range(at: 1), in: result), match.range(at: 1).location != NSNotFound {
                filename = String(result[range1])
            } else if let range2 = Range(match.range(at: 2), in: result), match.range(at: 2).location != NSNotFound {
                filename = String(result[range2])
            } else {
                continue
            }

            // Lowercase the extension part
            let normalizedFilename = lowercaseExtension(filename)
            result.replaceSubrange(fullRange, with: "@" + normalizedFilename)
        }

        return result
    }

    /// Lowercases the file extension portion of a filename.
    /// "index.HTML" → "index.html",  "App.TSX" → "App.tsx"
    private static func lowercaseExtension(_ filename: String) -> String {
        guard let dotIndex = filename.lastIndex(of: ".") else { return filename }
        let name = filename[filename.startIndex..<dotIndex]
        let ext = filename[filename.index(after: dotIndex)...]
        return String(name) + "." + ext.lowercased()
    }

    // MARK: - Public API

    /// Run all system-level post-processing rules on transcribed text.
    static func process(_ text: String) -> String {
        var result = text
        result = applyFileTags(result)
        return result
    }
}
