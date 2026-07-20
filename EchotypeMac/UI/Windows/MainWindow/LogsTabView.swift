//
//  LogsTabView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  Shows the in-app debug log (AppLog) with a Copy button so the user can grab
//  the full log and paste it back for debugging, without needing Xcode.
//

import SwiftUI
import AppKit

struct LogsTabView: View {
    @ObservedObject private var appLog = AppLog.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header + actions
            HStack(alignment: .center) {
                Text("Logs")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                dsCardButton(icon: copied ? "checkmark" : "doc.on.doc",
                             label: copied ? "Copied" : "Copy") {
                    copyLog()
                }
                dsCardButton(icon: "trash", label: "Clear") {
                    appLog.clear()
                }
            }
            .padding(.bottom, 8)

            Text("Recent activity — copy this and share it if something goes wrong.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.40))
                .padding(.bottom, 14)

            // Log body
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if appLog.entries.isEmpty {
                            Text("No log entries yet. Try a recording, then come back here.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.35))
                                .padding(.vertical, 8)
                        }
                        ForEach(appLog.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(timeString(entry.date))
                                    .foregroundStyle(Color.white.opacity(0.30))
                                Text("[\(entry.category)]")
                                    .foregroundStyle(color(for: entry.category))
                                Text(entry.message)
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .onChange(of: appLog.entries.count) { _, _ in
                    if let last = appLog.entries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(24)
    }

    private func copyLog() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(appLog.entriesText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func color(for category: String) -> Color {
        if category.hasPrefix("GPT") { return Color(red: 0.6, green: 0.8, blue: 1.0) }
        switch category {
        case "OpenAI": return Color(red: 0.5, green: 0.9, blue: 0.6)
        case "AppState": return Color(red: 1.0, green: 0.8, blue: 0.5)
        default: return Color.white.opacity(0.5)
        }
    }
}

#Preview("Logs") {
    LogsTabView()
        .frame(width: 600, height: 500)
        .background(Color.black)
        .onAppear {
            // Seed a couple of entries so the canvas shows the populated state.
            AppLog.shared.log("Preview", "example log line")
            AppLog.shared.log("OpenAI", "upload 0.42 MB, model=gpt-4o-transcribe")
        }
}
