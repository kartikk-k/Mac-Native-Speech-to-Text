//
//  UsageTracker.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//

import Foundation

@Observable
class UsageTracker {

    // MARK: - Persisted Stats

    var totalWords: Int = 0
    var totalSessions: Int = 0
    var totalCharacters: Int = 0
    var todayWords: Int = 0
    var todaySessions: Int = 0
    var currentStreak: Int = 0
    var lastSessionDate: Date? = nil
    var averageWordsPerMinute: Double = 0.0
    var totalRecordingSeconds: Double = 0.0

    /// Single, rounded WPM value for display everywhere (Home, Stats, etc.) so the
    /// same number always shows. Rounds rather than truncates.
    var wordsPerMinute: Int { Int(averageWordsPerMinute.rounded()) }

    // MARK: - Private

    @ObservationIgnored
    private let defaults = UserDefaults.standard

    @ObservationIgnored
    private let calendar = Calendar.current

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let totalWords = "usage_totalWords"
        static let totalSessions = "usage_totalSessions"
        static let totalCharacters = "usage_totalCharacters"
        static let todayWords = "usage_todayWords"
        static let todaySessions = "usage_todaySessions"
        static let currentStreak = "usage_currentStreak"
        static let lastSessionDate = "usage_lastSessionDate"
        static let averageWordsPerMinute = "usage_averageWordsPerMinute"
        static let totalRecordingSeconds = "usage_totalRecordingSeconds"
        static let lastTrackedDay = "usage_lastTrackedDay"
    }

    // MARK: - Init

    init() {
        totalWords = defaults.integer(forKey: Keys.totalWords)
        totalSessions = defaults.integer(forKey: Keys.totalSessions)
        totalCharacters = defaults.integer(forKey: Keys.totalCharacters)
        todayWords = defaults.integer(forKey: Keys.todayWords)
        todaySessions = defaults.integer(forKey: Keys.todaySessions)
        currentStreak = defaults.integer(forKey: Keys.currentStreak)
        averageWordsPerMinute = defaults.double(forKey: Keys.averageWordsPerMinute)
        totalRecordingSeconds = defaults.double(forKey: Keys.totalRecordingSeconds)

        if let timestamp = defaults.object(forKey: Keys.lastSessionDate) as? Date {
            lastSessionDate = timestamp
        }

        resetTodayIfNeeded()
    }

    // MARK: - Public Methods

    func recordSession(text: String, recordingDuration: TimeInterval) {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let wordCount = words.count
        let charCount = text.count

        // Update totals
        totalWords += wordCount
        totalSessions += 1
        totalCharacters += charCount
        totalRecordingSeconds += recordingDuration

        // Update today counters
        resetTodayIfNeeded()
        todayWords += wordCount
        todaySessions += 1

        // Update average WPM
        if totalRecordingSeconds > 0 {
            let totalMinutes = totalRecordingSeconds / 60.0
            averageWordsPerMinute = Double(totalWords) / totalMinutes
        }

        // Update streak and last session date
        lastSessionDate = Date()
        updateStreak()

        // Persist everything
        save()
    }

    func resetTodayIfNeeded() {
        let todayString = dayString(from: Date())
        let lastTrackedDay = defaults.string(forKey: Keys.lastTrackedDay) ?? ""

        if todayString != lastTrackedDay {
            todayWords = 0
            todaySessions = 0
            defaults.set(todayString, forKey: Keys.lastTrackedDay)
        }
    }

    func updateStreak() {
        guard let last = lastSessionDate else {
            currentStreak = 1
            return
        }

        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: last)

        let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

        if daysBetween == 0 {
            // Same day — streak stays the same, but ensure at least 1
            if currentStreak == 0 {
                currentStreak = 1
            }
        } else if daysBetween == 1 {
            // Consecutive day — increment streak
            currentStreak += 1
        } else {
            // Gap of more than one day — reset streak
            currentStreak = 1
        }
    }

    // MARK: - Private Methods

    private func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func save() {
        defaults.set(totalWords, forKey: Keys.totalWords)
        defaults.set(totalSessions, forKey: Keys.totalSessions)
        defaults.set(totalCharacters, forKey: Keys.totalCharacters)
        defaults.set(todayWords, forKey: Keys.todayWords)
        defaults.set(todaySessions, forKey: Keys.todaySessions)
        defaults.set(currentStreak, forKey: Keys.currentStreak)
        defaults.set(lastSessionDate, forKey: Keys.lastSessionDate)
        defaults.set(averageWordsPerMinute, forKey: Keys.averageWordsPerMinute)
        defaults.set(totalRecordingSeconds, forKey: Keys.totalRecordingSeconds)
    }
}
