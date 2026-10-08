import Foundation

enum PaceCalculator {
    enum Target: Int, CaseIterable {
        case pace, distance, time

        var title: String {
            switch self {
            case .pace: return "페이스"
            case .distance: return "거리"
            case .time: return "시간"
            }
        }
    }

    struct Input {
        var distance = ""
        var paceMinutes = ""
        var paceSeconds = ""
        var hours = ""
        var minutes = ""
        var seconds = ""
    }

    enum ValidationError: Error, LocalizedError {
        case incomplete
        case invalidDistance
        case invalidPace
        case invalidTime
        case outOfRange

        var errorDescription: String? {
            switch self {
            case .incomplete: return nil
            case .invalidDistance: return "거리는 0보다 큰 숫자로 입력해 주세요."
            case .invalidPace: return "페이스는 0보다 커야 하며, 초는 0~59로 입력해 주세요."
            case .invalidTime: return "시간은 0보다 커야 하며, 분과 초는 0~59로 입력해 주세요."
            case .outOfRange: return "입력값이 너무 크거나 작습니다."
            }
        }
    }

    static func calculate(_ target: Target, input: Input) throws -> Double {
        let result: Double
        switch target {
        case .pace:
            result = try duration(input) / distance(input.distance)
        case .distance:
            result = try duration(input) / pace(input)
        case .time:
            result = try pace(input) * distance(input.distance)
        }
        // Keep conversion to whole seconds safe and avoid a positive result displaying as zero.
        let minimum = target == .distance ? 0.0005 : 0.5
        guard result.isFinite, result >= minimum, result < 1_000_000_000 else {
            throw ValidationError.outOfRange
        }
        return result
    }

    static func formatted(_ result: Double, for target: Target) -> String {
        switch target {
        case .distance:
            return String(format: "%.3f km", result)
        case .pace:
            let seconds = Int(result.rounded())
            return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
        case .time:
            let seconds = Int(result.rounded())
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
    }

    private static func distance(_ text: String) throws -> Double {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ValidationError.incomplete }
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard normalized.allSatisfy({ "0123456789.".contains($0) }),
              let value = Double(normalized), value.isFinite, value > 0 else {
            throw ValidationError.invalidDistance
        }
        return value
    }

    private static func pace(_ input: Input) throws -> Double {
        guard !input.paceMinutes.isEmpty || !input.paceSeconds.isEmpty else {
            throw ValidationError.incomplete
        }
        guard let minutes = component(input.paceMinutes),
              let seconds = component(input.paceSeconds), seconds < 60 else {
            throw ValidationError.invalidPace
        }
        let value = minutes * 60 + seconds
        guard value > 0 else { throw ValidationError.invalidPace }
        return value
    }

    private static func duration(_ input: Input) throws -> Double {
        guard !input.hours.isEmpty || !input.minutes.isEmpty || !input.seconds.isEmpty else {
            throw ValidationError.incomplete
        }
        guard let hours = component(input.hours),
              let minutes = component(input.minutes), minutes < 60,
              let seconds = component(input.seconds), seconds < 60 else {
            throw ValidationError.invalidTime
        }
        let value = hours * 3600 + minutes * 60 + seconds
        guard value > 0 else { throw ValidationError.invalidTime }
        return value
    }

    private static func component(_ text: String) -> Double? {
        if text.isEmpty { return 0 }
        guard text.allSatisfy({ "0123456789".contains($0) }),
              let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
