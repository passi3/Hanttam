//
//  AnalyticsEventLogger.swift
//  Hanttam
//
//  Created by passi on 7/21/26.
//

import Foundation

#if os(iOS)
import FirebaseAnalytics
#endif

enum AnalyticsEventLogger {
    enum WorkoutSource: String {
        case phone
        case watch
    }

    enum SupabaseStatus: String {
        case success
        case failure
    }

    static func logWorkoutStart(
        kind: String,
        source: WorkoutSource,
        isIndoor: Bool? = nil,
        totalSets: Int? = nil,
        lapDistance: Double? = nil,
        restDuration: TimeInterval? = nil
    ) {
        var parameters = baseWorkoutParameters(kind: kind, source: source)
        add(isIndoor, key: "is_indoor", to: &parameters)
        add(totalSets, key: "total_sets", to: &parameters)
        add(lapDistance, key: "lap_distance_m", to: &parameters)
        add(restDuration, key: "rest_duration_sec", to: &parameters)
        logEvent("workout_start", parameters: parameters)
    }

    static func logWorkoutPause(
        kind: String,
        source: WorkoutSource,
        elapsed: TimeInterval? = nil,
        totalDistance: Double? = nil
    ) {
        var parameters = baseWorkoutParameters(kind: kind, source: source)
        add(elapsed, key: "elapsed_sec", to: &parameters)
        add(totalDistance, key: "total_distance_m", to: &parameters)
        logEvent("workout_pause", parameters: parameters)
    }

    static func logWorkoutEnd(
        kind: String,
        source: WorkoutSource,
        elapsed: TimeInterval,
        totalDistance: Double,
        shouldSave: Bool? = nil,
        saveSucceeded: Bool? = nil,
        error: Error? = nil
    ) {
        var parameters = baseWorkoutParameters(kind: kind, source: source)
        add(elapsed, key: "elapsed_sec", to: &parameters)
        add(totalDistance, key: "total_distance_m", to: &parameters)
        add(shouldSave, key: "should_save", to: &parameters)
        add(saveSucceeded, key: "save_succeeded", to: &parameters)
        if let error {
            parameters["error_type"] = String(describing: type(of: error))
        }
        logEvent("workout_end", parameters: parameters)
    }

    static func logSupabaseAPICall(
        operation: String,
        target: String,
        status: SupabaseStatus,
        duration: TimeInterval,
        resultCount: Int? = nil,
        error: Error? = nil
    ) {
        var parameters: [String: Any] = [
            "operation": operation,
            "target": target,
            "status": status.rawValue,
            "duration_ms": Int((duration * 1000).rounded())
        ]
        add(resultCount, key: "result_count", to: &parameters)
        if let error {
            parameters["error_type"] = String(describing: type(of: error))
        }
        logEvent("supabase_api_call", parameters: parameters)
    }

    private static func baseWorkoutParameters(kind: String, source: WorkoutSource) -> [String: Any] {
        [
            "workout_kind": kind,
            "source": source.rawValue
        ]
    }

    private static func add(_ value: Bool?, key: String, to parameters: inout [String: Any]) {
        guard let value else { return }
        parameters[key] = NSNumber(value: value)
    }

    private static func add(_ value: Int?, key: String, to parameters: inout [String: Any]) {
        guard let value else { return }
        parameters[key] = value
    }

    private static func add(_ value: Double?, key: String, to parameters: inout [String: Any]) {
        guard let value, value.isFinite else { return }
        parameters[key] = value
    }

    private static func logEvent(_ name: String, parameters: [String: Any]) {
#if os(iOS)
        Analytics.logEvent(name, parameters: parameters)
#else
        _ = name
        _ = parameters
#endif
    }
}
