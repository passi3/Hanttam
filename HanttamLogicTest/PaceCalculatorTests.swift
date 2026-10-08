import XCTest
@testable import Hanttam

final class PaceCalculatorTests: XCTestCase {
    func testCalculatesEachTarget() throws {
        let input = PaceCalculator.Input(distance: "10", paceMinutes: "5", minutes: "50")
        XCTAssertEqual(try PaceCalculator.calculate(.pace, input: input), 300)
        XCTAssertEqual(try PaceCalculator.calculate(.distance, input: input), 10)
        XCTAssertEqual(try PaceCalculator.calculate(.time, input: input), 3000)
    }

    func testMarathonTimeAndDecimalDistance() throws {
        let input = PaceCalculator.Input(distance: "42.195", paceMinutes: "5", paceSeconds: "30")
        let seconds = try PaceCalculator.calculate(.time, input: input)
        XCTAssertEqual(seconds, 13924.35, accuracy: 0.001)
        XCTAssertEqual(PaceCalculator.formatted(seconds, for: .time), "3:52:04")
        XCTAssertEqual(try PaceCalculator.calculate(.time, input: .init(distance: "1,5", paceMinutes: "5")), 450)
    }

    func testRoundingCarriesIntoMinutesAndHours() {
        XCTAssertEqual(PaceCalculator.formatted(299.6, for: .pace), "5:00 /km")
        XCTAssertEqual(PaceCalculator.formatted(3599.6, for: .time), "1:00:00")
        XCTAssertEqual(PaceCalculator.formatted(1.23456, for: .distance), "1.235 km")
    }

    func testRejectsInvalidValues() {
        for distance in ["0", "-1", "NaN", "inf", "1.2.3"] {
            XCTAssertThrowsError(try PaceCalculator.calculate(.pace, input: .init(distance: distance, minutes: "30")))
        }
        XCTAssertThrowsError(try PaceCalculator.calculate(.distance, input: .init(paceMinutes: "0", minutes: "30")))
        XCTAssertThrowsError(try PaceCalculator.calculate(.time, input: .init(distance: "5", paceSeconds: "60")))
        XCTAssertThrowsError(try PaceCalculator.calculate(.pace, input: .init(distance: "5", minutes: "60")))
        XCTAssertThrowsError(try PaceCalculator.calculate(.pace, input: .init(distance: "5", seconds: "-1")))
        XCTAssertThrowsError(try PaceCalculator.calculate(.time, input: .init(distance: "1e300", paceMinutes: "5")))
    }

    func testMissingInputAndIgnoredTargetValue() throws {
        XCTAssertThrowsError(try PaceCalculator.calculate(.pace, input: .init(distance: "5"))) { error in
            XCTAssertEqual(error as? PaceCalculator.ValidationError, .incomplete)
        }
        let input = PaceCalculator.Input(distance: "5", paceMinutes: "invalid", minutes: "25")
        XCTAssertEqual(try PaceCalculator.calculate(.pace, input: input), 300)
    }
}
