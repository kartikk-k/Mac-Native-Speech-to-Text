//
//  SidebarView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: MainTab
    @EnvironmentObject private var failedStore: FailedTranscriptionStore

    private let mainNav: [MainTab] = [.home, .history, .learn, .snippets, .stats]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Overview")
                    navSection(items: mainNav)

                    sectionHeader("More")
                        .padding(.top, 12)
                    navSection(items: [.logs, .invite])
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
            }

            // Settings pinned at bottom
            navRow(tab: .settings, isSelected: selectedTab == .settings)
                .onTapGesture { selectedTab = .settings }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
                .padding(.top, 6)
        }
        .frame(width: 200)
        .background(.ultraThickMaterial)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func navSection(items: [MainTab]) -> some View {
        VStack(spacing: 1) {
            ForEach(items, id: \.self) { tab in
                navRow(tab: tab, isSelected: selectedTab == tab)
                    .onTapGesture { selectedTab = tab }
            }
        }
        .padding(.horizontal, 8)
    }

    private func navRow(tab: MainTab, isSelected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: tab.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                .frame(width: 20, alignment: .center)

            Text(tab.rawValue)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(isSelected ? .white : Color.white.opacity(0.75))

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.35))
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
    }
}

#Preview("Sidebar") {
    SidebarView(selectedTab: .constant(.home))
        .environmentObject(FailedTranscriptionStore())
        .frame(height: 500)
}
