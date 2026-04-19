//
//  WorkoutNotificationServiceTests.swift
//  HanttamLogicTest
//
//  외부 러닝 데이터가 들어왔을 때 UNNotificationRequest가 정상적으로 추가되는지 검증.
//  실제 HealthKit 기기/앱 없이 HKWorkout을 직접 생성하고
//  Mock 의존성을 주입해서 테스트합니다.
//

import XCTest
import HealthKit
import UserNotifications
@testable import Hanttam

// MARK: - Mock: UNUserNotificationCenter 대역

final class MockNotificationCenter: NotificationScheduling {
    /// add() 가 호출된 요청 목록
    private(set) var addedRequests: [UNNotificationRequest] = []
    /// 다음 add() 호출 시 completionHandler 에 넘길 에러 (기본 nil = 성공)
    var stubbedError: Error?

    func add(_ request: UNNotificationRequest,
             withCompletionHandler completionHandler: ((Error?) -> Void)?) {
        addedRequests.append(request)
        completionHandler?(stubbedError)
    }

    func reset() { addedRequests = [] }
}

// MARK: - Mock: GearLocalStore 대역

final class MockGearStore: GearLocalStoring {
    var shoes: [RegisteredShoe] = []
    func fetchRegisteredShoes() -> [RegisteredShoe] { shoes }
    func saveRegisteredShoe(_ shoe: RegisteredShoe) {}
    func updateRegisteredShoe(_ shoe: RegisteredShoe) {}
    func deleteRegisteredShoe(id: UUID) {}
    func fetchSessionLinks() -> [ShoeSessionLink] { [] }
    func upsertSessionLink(_ link: ShoeSessionLink) {}
    func removeSessionLink(sessionIdentifier: String, kind: GearSessionKind) {}
    func linkedShoe(for sessionIdentifier: String, kind: GearSessionKind) -> RegisteredShoe? { nil }
}

// MARK: - Test Helpers

extension HKWorkout {
    /// 테스트용 러닝 워크아웃 생성
    static func makeRunning(duration: TimeInterval = 1800) -> HKWorkout {
        HKWorkout(
            activityType: .running,
            start: Date(timeIntervalSinceNow: -duration),
            end: Date()
        )
    }

    /// 테스트용 비러닝 워크아웃 생성
    static func makeCycling(duration: TimeInterval = 3600) -> HKWorkout {
        HKWorkout(
            activityType: .cycling,
            start: Date(timeIntervalSinceNow: -duration),
            end: Date()
        )
    }
}

// MARK: - Tests

final class WorkoutNotificationServiceTests: XCTestCase {

    var mockCenter: MockNotificationCenter!
    var mockGearStore: MockGearStore!
    /// ownBundleIDs = [] → 어떤 워크아웃도 "외부"로 간주 (필터 통과)
    var service: WorkoutNotificationService!

    override func setUp() {
        super.setUp()
        mockCenter   = MockNotificationCenter()
        mockGearStore = MockGearStore()
        service = WorkoutNotificationService(
            notificationCenter: mockCenter,
            gearStore: mockGearStore,
            ownBundleIDs: [] // 빈 세트 → 모든 번들을 외부로 취급
        )
    }

    override func tearDown() {
        mockCenter   = nil
        mockGearStore = nil
        service      = nil
        super.tearDown()
    }

    // MARK: sendPhotoNotification 직접 호출

    func test_sendPhotoNotification_addsOneRequest() {
        let workout = HKWorkout.makeRunning()
        service.sendPhotoNotification(for: workout)
        XCTAssertEqual(mockCenter.addedRequests.count, 1,
                       "러닝 워크아웃 1개에 알림 요청이 1개 추가되어야 합니다")
    }

    func test_sendPhotoNotification_requestIdentifierContainsUUID() {
        let workout = HKWorkout.makeRunning()
        service.sendPhotoNotification(for: workout)

        let request = mockCenter.addedRequests.first!
        XCTAssertTrue(
            request.identifier.contains(workout.uuid.uuidString),
            "알림 식별자에 워크아웃 UUID가 포함되어야 합니다"
        )
    }

    func test_sendPhotoNotification_userInfoContainsWorkoutUUID() {
        let workout = HKWorkout.makeRunning()
        service.sendPhotoNotification(for: workout)

        let userInfo = mockCenter.addedRequests.first!.content.userInfo
        let storedUUID = userInfo[WorkoutNotificationService.workoutUUIDKey] as? String

        XCTAssertEqual(storedUUID, workout.uuid.uuidString,
                       "userInfo 에 워크아웃 UUID 가 저장되어야 합니다")
    }

    func test_sendPhotoNotification_title() {
        service.sendPhotoNotification(for: .makeRunning())
        XCTAssertEqual(mockCenter.addedRequests.first?.content.title, "운동 완료! 💪")
    }

    func test_sendPhotoNotification_bodyWithGear() {
        mockGearStore.shoes = [RegisteredShoe.stub()]
        service.sendPhotoNotification(for: .makeRunning())
        XCTAssertEqual(
            mockCenter.addedRequests.first?.content.body,
            "어떤 신발로 뛰었는지 기록해보세요!",
            "장비가 있을 때는 장비 관련 메시지를 표시해야 합니다"
        )
    }

    func test_sendPhotoNotification_bodyWithoutGear() {
        mockGearStore.shoes = []
        service.sendPhotoNotification(for: .makeRunning())
        XCTAssertEqual(
            mockCenter.addedRequests.first?.content.body,
            "방금 운동한 기록을 사진으로 남겨보세요!",
            "장비가 없을 때는 사진 기록 메시지를 표시해야 합니다"
        )
    }

    func test_sendMultipleWorkouts_addsMultipleRequests() {
        service.sendPhotoNotification(for: .makeRunning())
        service.sendPhotoNotification(for: .makeRunning())
        XCTAssertEqual(mockCenter.addedRequests.count, 2)
    }

    // MARK: isExternalRunning 필터

    func test_isExternalRunning_runningWorkout_returnsTrue() {
        // ownBundleIDs = [] 이므로 어떤 번들도 자체 앱으로 분류되지 않음
        let workout = HKWorkout.makeRunning()
        XCTAssertTrue(service.isExternalRunning(workout),
                      "러닝 워크아웃은 외부로 분류되어야 합니다")
    }

    func test_isExternalRunning_nonRunningWorkout_returnsFalse() {
        let workout = HKWorkout.makeCycling()
        XCTAssertFalse(service.isExternalRunning(workout),
                       "러닝이 아닌 워크아웃은 외부로 분류되지 않아야 합니다")
    }

    func test_isExternalRunning_ownBundleRunning_returnsFalse() {
        let workout = HKWorkout.makeRunning()
        let ownBundle = workout.sourceRevision.source.bundleIdentifier

        let serviceWithOwn = WorkoutNotificationService(
            notificationCenter: mockCenter,
            gearStore: mockGearStore,
            ownBundleIDs: [ownBundle]
        )

        XCTAssertFalse(serviceWithOwn.isExternalRunning(workout),
                       "자체 앱 번들의 워크아웃은 알림 대상에서 제외되어야 합니다")
    }

    // MARK: 필터 + 알림 통합

    func test_nonRunningWorkout_doesNotSendNotification() {
        // 사이클링 워크아웃은 isExternalRunning = false → sendPhotoNotification 호출 안 됨
        let cycling = HKWorkout.makeCycling()
        // isExternalRunning 이 false 인지 먼저 확인
        XCTAssertFalse(service.isExternalRunning(cycling))
        // 실제 파이프라인에서는 false 면 send 를 호출하지 않으므로 직접 검증
        // (checkForNewRunningWorkouts 내 filter 로직을 단위 수준으로 재현)
        let shouldSend = service.isExternalRunning(cycling)
        if shouldSend { service.sendPhotoNotification(for: cycling) }
        XCTAssertEqual(mockCenter.addedRequests.count, 0,
                       "러닝이 아닌 운동에 대해서는 알림이 추가되지 않아야 합니다")
    }

    func test_runningWorkout_sendNotification_fullPipeline() {
        let running = HKWorkout.makeRunning()
        let shouldSend = service.isExternalRunning(running)
        if shouldSend { service.sendPhotoNotification(for: running) }
        XCTAssertEqual(mockCenter.addedRequests.count, 1,
                       "외부 러닝 워크아웃은 파이프라인을 통해 알림이 1개 추가되어야 합니다")
    }
}

// MARK: - RegisteredShoe Test Stub

private extension RegisteredShoe {
    static func stub() -> RegisteredShoe {
        RegisteredShoe(
            catalogID: "test-catalog",
            brandName: "Nike",
            modelName: "Pegasus 41",
            sku: "TEST-SKU",
            colors: [],
            imageURL: nil,
            createdAt: nil,
            targetDistanceMeters: 500_000
        )
    }
}
