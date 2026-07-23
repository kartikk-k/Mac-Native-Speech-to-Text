//
//  LearnTabView.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/9/26.
//

import SwiftUI

private enum LearnStep: Int, CaseIterable {
    case holdToSpeak = 0
    case startHandsFree
    case stopHandsFree
    case cancelRecording

    var title: String {
        switch self {
        case .holdToSpeak: return "Hold to Dictate"
        case .startHandsFree: return "Start Hands-Free"
        case .stopHandsFree: return "Stop Hands-Free"
        case .cancelRecording: return "Cancel Recording"
        }
    }

    var icon: String {
        switch self {
        case .holdToSpeak: return "globe"
        case .startHandsFree: return "hand.raised"
        case .stopHandsFree: return "stop.circle"
        case .cancelRecording: return "delete.backward"
        }
    }

    var instruction: String {
        switch self {
        case .holdToSpeak:
            return "Hold the Globe (Fn) key and speak. When you release, your speech will be transcribed and inserted."
        case .startHandsFree:
            return "Press Globe (Fn) + Space together to start hands-free recording. You can let go of all keys and keep talking."
        case .stopHandsFree:
            return "While in hands-free mode, press Space or Escape to stop recording. The text will be transcribed and inserted."
        case .cancelRecording:
            return "Press Delete (Backspace) while recording to cancel. Nothing will be transcribed or inserted."
        }
    }

    var waitingPrompt: String {
        switch self {
        case .holdToSpeak: return "Hold the Fn key to start..."
        case .startHandsFree: return "Press Fn + Space to start hands-free..."
        case .stopHandsFree: return "First start hands-free mode (Fn + Space)..."
        case .cancelRecording: return "Start recording (hold Fn or use hands-free)..."
        }
    }

    var activePrompt: String {
        switch self {
        case .holdToSpeak: return "Recording! Speak now, then release Fn..."
        case .startHandsFree: return "Hands-free mode active!"
        case .stopHandsFree: return "Now press Space or Escape to stop..."
        case .cancelRecording: return "Now press Delete to cancel..."
        }
    }

    var donePrompt: String {
        switch self {
        case .holdToSpeak: return "You did it! Text was transcribed and inserted."
        case .startHandsFree: return "Hands-free mode activated!"
        case .stopHandsFree: return "You stopped hands-free and text was inserted."
        case .cancelRecording: return "Recording cancelled — nothing was inserted."
        }
    }
}

struct LearnTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep: LearnStep = .holdToSpeak
    @State private var stepCompleted: Set<LearnStep> = []
    @State private var practiceText = ""

    // Track sub-states for multi-part steps
    @State private var handsFreeStartedForStop = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                Text("Learn")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)

                Text("Interactive tutorial — try each action and see it work in real time.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.bottom, 8)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10.5))
                    Text("These shortcuts use the Globe (Fn) key on Apple keyboards. On a keyboard without Fn/Globe, set a custom hotkey in Settings.")
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.bottom, 24)

                // Step pills
                HStack(spacing: 8) {
                    ForEach(LearnStep.allCases, id: \.rawValue) { step in
                        stepPill(step: step)
                    }
                    Spacer()
                }
                .padding(.bottom, 20)

                // Current step card
                dsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: currentStep.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.10))
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Step \(currentStep.rawValue + 1) of \(LearnStep.allCases.count)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.40))
                                Text(currentStep.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            Spacer()

                            if stepCompleted.contains(currentStep) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.green)
                            }
                        }

                        dsDivider()

                        Text(currentStep.instruction)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white)
                            .lineSpacing(4)

                        // Live status indicator
                        statusBadge
                    }
                }

                // Practice area
                dsSectionHeader(icon: "text.cursor", title: "Practice Area")

                dsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Click here and try the current step:")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.40))

                        TextEditor(text: $practiceText)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100, maxHeight: 160)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                    )
                            )

                        HStack {
                            Button(action: { practiceText = "" }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 10, weight: .medium))
                                    Text("Clear")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(Color.white.opacity(0.50))
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                    }
                }

                // Navigation
                HStack(spacing: 12) {
                    if currentStep.rawValue > 0 {
                        Button(action: { prevStep() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Previous")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(Color.white.opacity(0.60))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if currentStep.rawValue < LearnStep.allCases.count - 1 {
                        Button(action: { nextStep() }) {
                            HStack(spacing: 5) {
                                Text("Next")
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        let allDone = stepCompleted.count == LearnStep.allCases.count
                        HStack(spacing: 6) {
                            Image(systemName: allDone ? "party.popper.fill" : "checkmark.seal")
                                .font(.system(size: 13))
                            Text(allDone ? "All done! You're ready." : "Complete all steps to finish")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(allDone ? .green : Color.white.opacity(0.50))
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 36)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .onChange(of: appState.phase) { oldPhase, newPhase in
            handlePhaseChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: appState.isHandsFree) { _, isHandsFree in
            handleHandsFreeChange(isHandsFree)
        }
        .onChange(of: appState.lastEndReason) { _, reason in
            handleEndReason(reason)
        }
    }

    // MARK: - Live Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        let (icon, text, color) = statusInfo
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(color)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(color.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var statusInfo: (String, String, Color) {
        if stepCompleted.contains(currentStep) {
            return ("checkmark.circle.fill", currentStep.donePrompt, .green)
        }

        switch currentStep {
        case .holdToSpeak:
            if appState.phase == .listening && !appState.isHandsFree {
                return ("mic.fill", currentStep.activePrompt, .orange)
            } else if appState.phase == .processing {
                return ("waveform", "Processing your speech...", .blue)
            }
        case .startHandsFree:
            if appState.isHandsFree {
                return ("checkmark.circle.fill", currentStep.activePrompt, .green)
            } else if appState.phase == .listening {
                return ("mic.fill", "Listening... now press Fn + Space", .orange)
            }
        case .stopHandsFree:
            if appState.isHandsFree {
                return ("mic.fill", currentStep.activePrompt, .orange)
            } else if appState.phase == .listening && !handsFreeStartedForStop {
                return ("mic.fill", "Now activate hands-free with Fn + Space...", .yellow)
            } else if appState.phase == .processing {
                return ("waveform", "Processing...", .blue)
            }
        case .cancelRecording:
            if appState.phase == .listening {
                return ("mic.fill", currentStep.activePrompt, .orange)
            }
        }

        return ("circle", currentStep.waitingPrompt, Color.white.opacity(0.40))
    }

    // MARK: - State Tracking

    private func handlePhaseChange(from oldPhase: RecognitionPhase, to newPhase: RecognitionPhase) {
        // Step 3: track that user entered hands-free for the stop step
        if currentStep == .stopHandsFree && newPhase == .listening && appState.isHandsFree {
            handsFreeStartedForStop = true
        }
    }

    private func handleHandsFreeChange(_ isHandsFree: Bool) {
        // Step 2: detect hands-free activation
        if currentStep == .startHandsFree && isHandsFree {
            completeStep(.startHandsFree)
        }

        // Step 3: track entering hands-free
        if currentStep == .stopHandsFree && isHandsFree {
            handsFreeStartedForStop = true
        }
    }

    private func handleEndReason(_ reason: SessionEndReason) {
        guard reason != .none else { return }

        switch currentStep {
        case .holdToSpeak:
            if reason == .released {
                completeStep(.holdToSpeak)
            }
        case .stopHandsFree:
            if reason == .handsFreeStop && handsFreeStartedForStop {
                completeStep(.stopHandsFree)
                handsFreeStartedForStop = false
            }
        case .cancelRecording:
            if reason == .cancelled {
                completeStep(.cancelRecording)
            }
        default:
            break
        }

        // Reset for next use
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            appState.lastEndReason = .none
        }
    }

    private func completeStep(_ step: LearnStep) {
        withAnimation(.easeInOut(duration: 0.3)) {
            stepCompleted.insert(step)
        }
        // Auto-advance after a short delay
        if step == currentStep && currentStep.rawValue < LearnStep.allCases.count - 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                nextStep()
            }
        }
    }

    // MARK: - Step Pill

    private func stepPill(step: LearnStep) -> some View {
        Button(action: { currentStep = step }) {
            HStack(spacing: 5) {
                if stepCompleted.contains(step) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(currentStep == step ? .white : Color.white.opacity(0.40))
                }

                // Always show the title so users know what each step is, not
                // just an anonymous number.
                Text(step.title)
                    .font(.system(size: 11.5, weight: currentStep == step ? .medium : .regular))
                    .foregroundStyle(currentStep == step ? .white : Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(currentStep == step ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                stepCompleted.contains(step) ? Color.green.opacity(0.30) :
                                    (currentStep == step ? Color.white.opacity(0.15) : Color.white.opacity(0.08)),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: currentStep)
    }

    // MARK: - Navigation

    private func nextStep() {
        if let next = LearnStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
            practiceText = ""
            // If already in hands-free when arriving at Step 3, count it
            handsFreeStartedForStop = (next == .stopHandsFree && appState.isHandsFree)
        }
    }

    private func prevStep() {
        if let prev = LearnStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
            practiceText = ""
            handsFreeStartedForStop = false
        }
    }
}

#Preview("Learn") {
    LearnTabView()
        .environmentObject(AppState())
        .frame(width: 600, height: 600)
}
