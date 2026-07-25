//
//  SnippetsTabView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/9/26.
//

import SwiftUI

struct SnippetsTabView: View {
    @Environment(SnippetManager.self) private var snippetManager

    @State private var newTrigger = ""
    @State private var newReplacement = ""
    @State private var editingSnippetID: UUID?
    @State private var editTrigger = ""
    @State private var editReplacement = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                Text("Snippets")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)

                Text("When you say a trigger phrase, it gets replaced with your snippet text.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.bottom, 6)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10.5))
                    Text("Matching is case-insensitive and matches the phrase anywhere in your dictation.")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.bottom, 20)

                // Add new snippet
                dsSectionHeader(icon: "plus.circle", title: "Add Snippet")

                dsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trigger phrase")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.40))
                            TextField("e.g. my email address", text: $newTrigger)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13.5))
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                        )
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Replace with")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.40))
                            TextField("e.g. hello@example.com", text: $newReplacement)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13.5))
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                        )
                                )
                        }

                        HStack {
                            Spacer()
                            let isValid = !newTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                                && !newReplacement.trimmingCharacters(in: .whitespaces).isEmpty
                            Button(action: addSnippet) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11.5, weight: .medium))
                                    Text("Add Snippet")
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundStyle(isValid ? Color.white : Color.white.opacity(0.45))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isValid ? Color.accentColor : Color.white.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!isValid)
                            .animation(.easeInOut(duration: 0.12), value: isValid)
                        }
                    }
                }

                // Existing snippets
                dsSectionHeader(icon: "text.quote", title: "Your Snippets")

                if snippetManager.snippets.isEmpty {
                    dsCard {
                        HStack(spacing: 12) {
                            Image(systemName: "text.badge.plus")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.white.opacity(0.40))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No snippets yet")
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(.white)
                                Text("Add a snippet above to get started.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.40))
                            }
                            Spacer()
                        }
                    }
                } else {
                    dsCard {
                        VStack(spacing: 0) {
                            ForEach(Array(snippetManager.snippets.enumerated()), id: \.element.id) { index, snippet in
                                if index > 0 {
                                    dsDivider()
                                        .padding(.vertical, 10)
                                }

                                if editingSnippetID == snippet.id {
                                    editRow(snippet: snippet)
                                } else {
                                    snippetRow(snippet: snippet)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Snippet Row

    private func snippetRow(snippet: Snippet) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(snippet.trigger)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white)
                    Text("\u{2192}")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.30))
                    Text(snippet.replacement)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    editingSnippetID = snippet.id
                    editTrigger = snippet.trigger
                    editReplacement = snippet.replacement
                } label: {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 26, height: 26)
//                        .background(
//                            RoundedRectangle(cornerRadius: 6, style: .continuous)
//                                .fill(Color.white.opacity(0.06))
//                        )
                }
                .buttonStyle(.plain)

                Button {
                    snippetManager.delete(id: snippet.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 26, height: 26)
//                        .background(
//                            RoundedRectangle(cornerRadius: 6, style: .continuous)
//                                .fill(Color.red.opacity(0.08))
//                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Edit Row

    private func editRow(snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Trigger phrase", text: $editTrigger)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )

            TextField("Replace with", text: $editReplacement)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    editingSnippetID = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.50))

                Button("Save") {
                    var updated = snippet
                    updated.trigger = editTrigger
                    updated.replacement = editReplacement
                    snippetManager.update(updated)
                    editingSnippetID = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .disabled(editTrigger.isEmpty || editReplacement.isEmpty)
                .opacity(editTrigger.isEmpty || editReplacement.isEmpty ? 0.4 : 1.0)
            }
        }
    }

    // MARK: - Actions

    private func addSnippet() {
        snippetManager.add(trigger: newTrigger.trimmingCharacters(in: .whitespaces),
                           replacement: newReplacement.trimmingCharacters(in: .whitespaces))
        newTrigger = ""
        newReplacement = ""
    }
}

#Preview("Snippets") {
    SnippetsTabView()
        .environment(SnippetManager())
        .frame(width: 600, height: 500)
}
