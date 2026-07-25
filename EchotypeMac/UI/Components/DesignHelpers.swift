//
//  DesignHelpers.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import SwiftUI

// MARK: - Card

func dsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .center)
    .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    )
}

// MARK: - Section Header

func dsSectionHeader(icon: String, title: String) -> some View {
    HStack(spacing: 7) {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.40))
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.55))
    }
    .padding(.top, 24)
    .padding(.bottom, 10)
}

// MARK: - Divider

func dsDivider() -> some View {
    Rectangle()
        .fill(Color.white.opacity(0.07))
        .frame(height: 1)
}

func dsVerticalDivider() -> some View {
    Rectangle()
        .fill(Color.white.opacity(0.07))
        .frame(width: 1, height: 32)
}

// MARK: - Toggle Row

func dsToggleRow(icon: String, title: String, subtitle: String, binding: Binding<Bool>) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.6))
            .frame(width: 20)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.40))
        }
        Spacer()
        Toggle("", isOn: binding)
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

// MARK: - Card Button

func dsCardButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .medium))
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(0.80))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
    .buttonStyle(.plain)
}

// MARK: - Picker Row

func dsPickerRow(title: String, value: String, options: [String], onSelect: @escaping (String) -> Void) -> some View {
    HStack {
        Text(title)
            .font(.system(size: 13.5))
            .foregroundStyle(.white)
        Spacer()
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(opt) { onSelect(opt) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.70))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Formatters

func dsFormattedCount(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    } else if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

func dsFormattedTime(_ seconds: Double) -> String {
    let totalMinutes = Int(seconds) / 60
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

func dsFormattedStreak(_ days: Int) -> String {
    if days >= 7 {
        let weeks = days / 7
        let rem = days % 7
        return rem == 0 ? "\(weeks) week" : "\(weeks)w \(rem)d"
    }
    return days == 1 ? "1 day" : "\(days) days"
}
