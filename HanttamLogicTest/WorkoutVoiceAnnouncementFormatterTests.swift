//
//  WorkoutVoiceAnnouncementFormatterTests.swift
//  HanttamLogicTest
//
//  Created by passi on 7/16/26.
//

import XCTest
@testable import Hanttam

final class WorkoutVoiceAnnouncementFormatterTests: XCTestCase {
    func test_intervalLapCompletionText_containsRequestedFieldsOnly() {
        let summary = IntervalLapCompletionSummary(
            eventID: "lap-1",
            completedSet: 1,
            totalDistance: 1200,
            totalDuration: 3723,
            avgPace: 270,
            lapPace: 252,
            avgHeartRate: 158,
            lapHeartRate: 165
        )

        let text = WorkoutVoiceAnnouncementFormatter.intervalLapCompletionText(summary)

        XCTAssertEqual(
            text,
            "1세트 완료. 누적 거리 1.200킬로미터. 총 시간 한 시간 이분 삼초. 평균 페이스 킬로미터당 4분 30초. 랩 페이스 킬로미터당 4분 12초. 평균 심박 158. 랩 심박 165."
        )
        XCTAssertFalse(text.contains("휴식"))
        XCTAssertFalse(text.contains("칼로리"))
        XCTAssertTrue(text.contains("총 시간"))
    }

    func test_intervalLapCompletionText_omitsMissingPaceAndHeartRate() {
        let summary = IntervalLapCompletionSummary(
            eventID: "lap-2",
            completedSet: 2,
            totalDistance: 800,
            totalDuration: 65,
            avgPace: nil,
            lapPace: nil,
            avgHeartRate: nil,
            lapHeartRate: nil
        )

        let text = WorkoutVoiceAnnouncementFormatter.intervalLapCompletionText(summary)

        XCTAssertEqual(text, "2세트 완료. 누적 거리 0.800킬로미터. 총 시간 일분 오초.")
        XCTAssertFalse(text.contains("--"))
    }

    func test_workoutCompletionText_containsCompletionSummaryOnly() {
        let summary = WorkoutCompletionSummary(
            eventID: "workout-1",
            completedSets: 3,
            totalDistance: 1200,
            totalDuration: 3723,
            avgPace: 270,
            avgHeartRate: 158
        )

        let text = WorkoutVoiceAnnouncementFormatter.workoutCompletionText(summary)

        XCTAssertEqual(
            text,
            "운동 완료. 총 3세트. 총 거리 1.200킬로미터. 총 시간 한 시간 이분 삼초. 평균 페이스 킬로미터당 4분 30초. 평균 심박 158."
        )
        XCTAssertFalse(text.contains("랩 페이스"))
        XCTAssertFalse(text.contains("랩 심박"))
        XCTAssertFalse(text.contains("휴식"))
    }
}
