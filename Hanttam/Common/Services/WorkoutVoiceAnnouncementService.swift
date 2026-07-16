//
//  WorkoutVoiceAnnouncementService.swift
//  Hanttam
//
//  Created by passi on 7/16/26.
//

import AVFoundation
import Foundation

final class WorkoutVoiceAnnouncementService {
    static let shared = WorkoutVoiceAnnouncementService()

    private let synthesizer = AVSpeechSynthesizer()
    private var announcedEventIDs = Set<String>()

    private init() {}

    func announceIntervalLapCompletion(_ summary: IntervalLapCompletionSummary) {
        let text = WorkoutVoiceAnnouncementFormatter.intervalLapCompletionText(summary)
        speak(text, eventID: summary.eventID)
    }

    func announceWorkoutCompletion(_ summary: WorkoutCompletionSummary) {
        let text = WorkoutVoiceAnnouncementFormatter.workoutCompletionText(summary)
        speak(text, eventID: summary.eventID)
    }

    private func speak(_ text: String, eventID: String) {
        guard WorkoutVoiceAnnouncementPreferences.isEnabled else { return }
        guard announcedEventIDs.insert(eventID).inserted else { return }

        configureAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[WorkoutVoiceAnnouncement] audio session failed: \(error.localizedDescription)")
        }
    }
}
