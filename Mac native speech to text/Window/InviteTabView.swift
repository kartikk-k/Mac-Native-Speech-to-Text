//
//  InviteTabView.swift
//  Mac native speech to text
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

struct InviteTabView: View {
    private let githubURL = "https://github.com/kartikk-k/Echotype-Mac"

    @State private var copied = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                Text("Share")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)

                // Hero card
                dsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Share Echotype")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(.white)
                                Text("This app is free and open source. Share it with friends who could use better dictation on their Mac.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.40))
                            }
                            Spacer()
                        }
                    }
                }

                dsSectionHeader(icon: "square.and.arrow.up", title: "Actions")

                dsCard {
                    // Copy Link
                    HStack(spacing: 12) {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(copied ? .green : Color.white.opacity(0.6))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Repository Link")
                                .font(.system(size: 13.5))
                                .foregroundStyle(.white)
                            Text(githubURL)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.40))
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        dsCardButton(icon: copied ? "checkmark" : "doc.on.doc", label: copied ? "Copied!" : "Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(githubURL, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copied = false
                            }
                        }

                        dsCardButton(icon: "arrow.up.right.square", label: "Open in Browser") {
                            if let url = URL(string: githubURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        dsCardButton(icon: "message.fill", label: "Share via Messages") {
                            if let url = URL(string: githubURL) {
                                let service = NSSharingService(named: .composeMessage)
                                service?.perform(withItems: [
                                    "Check out Echotype — a free, open-source dictation app for macOS!" as NSString,
                                    url as NSURL
                                ])
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }
}

#Preview("Invite") {
    InviteTabView()
        .frame(width: 600, height: 500)
}
