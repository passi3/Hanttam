//
//  SettingsViewModel.swift
//  Hanttam
//
//  Created by passi on 4/19/26.
//

import Foundation
import UIKit
import RxSwift
import RxCocoa
import CoreLocation
import UserNotifications
internal import HealthKit

final class SettingsViewModel: HTReusableVMProtocol {

    // MARK: - Models

    enum PermissionKind: Int, CaseIterable {
        case healthKit
        case location
        case notification

        var title: String {
            switch self {
            case .healthKit:    return "건강 데이터"
            case .location:     return "위치"
            case .notification: return "알림"
            }
        }

        var iconName: String {
            switch self {
            case .healthKit:    return "heart.fill"
            case .location:     return "location.fill"
            case .notification: return "bell.fill"
            }
        }
    }

    enum PermissionStatus {
        case authorized, denied, notDetermined, unavailable
        var label: String {
            switch self {
            case .authorized:    return "허용"
            case .denied:        return "거부"
            case .notDetermined: return "미결정"
            case .unavailable:   return "미지원"
            }
        }
    }

    struct PermissionItem {
        let kind: PermissionKind
        let status: PermissionStatus
    }

    enum SettingsDestination {
        case healthApp
        case locationSettings
        case notificationSettings
    }

    // MARK: - I/O

    struct Input {
        let viewWillAppear: Observable<Void>
        let selectPermission: Observable<PermissionKind>
    }

    struct Output {
        let permissions: Driver<[PermissionItem]>
        let appVersion: Driver<String>
        let openDestination: Signal<SettingsDestination>
    }

    // MARK: - Private

    private let permissionsRelay = BehaviorRelay<[PermissionItem]>(value: [])
    private let openDestinationRelay = PublishRelay<SettingsDestination>()
    private let disposeBag = DisposeBag()

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let didBecomeActive = NotificationCenter.default.rx
            .notification(UIApplication.didBecomeActiveNotification)
            .map { _ in () }

        Observable.merge(input.viewWillAppear, didBecomeActive)
            .flatMapLatest { [weak self] _ -> Observable<[PermissionItem]> in
                self?.fetchPermissions() ?? .empty()
            }
            .bind(to: permissionsRelay)
            .disposed(by: disposeBag)

        input.selectPermission
            .map { kind -> SettingsDestination in
                switch kind {
                case .healthKit:    return .healthApp
                case .location:     return .locationSettings
                case .notification: return .notificationSettings
                }
            }
            .bind(to: openDestinationRelay)
            .disposed(by: disposeBag)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"

        return Output(
            permissions: permissionsRelay.asDriver(),
            appVersion: .just("\(version) (\(build))"),
            openDestination: openDestinationRelay.asSignal()
        )
    }

    // MARK: - Permission Fetching

    private func fetchPermissions() -> Observable<[PermissionItem]> {
        Observable.zip(
            healthKitStatus(),
            locationStatus(),
            notificationStatus()
        )
        .map { hk, loc, noti in
            [
                PermissionItem(kind: .healthKit,    status: hk),
                PermissionItem(kind: .location,     status: loc),
                PermissionItem(kind: .notification, status: noti)
            ]
        }
    }

    private func healthKitStatus() -> Observable<PermissionStatus> {
        Observable.create { observer in
            guard HKHealthStore.isHealthDataAvailable() else {
                observer.onNext(.unavailable)
                observer.onCompleted()
                return Disposables.create()
            }
            let status = HKHealthStore().authorizationStatus(for: HKObjectType.workoutType())
            switch status {
            case .sharingAuthorized: observer.onNext(.authorized)
            case .sharingDenied:     observer.onNext(.denied)
            default:                 observer.onNext(.notDetermined)
            }
            observer.onCompleted()
            return Disposables.create()
        }
    }

    private func locationStatus() -> Observable<PermissionStatus> {
        let status: PermissionStatus
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: status = .authorized
        case .denied, .restricted:                    status = .denied
        default:                                      status = .notDetermined
        }
        return .just(status)
    }

    private func notificationStatus() -> Observable<PermissionStatus> {
        Observable.create { observer in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: observer.onNext(.authorized)
                case .denied:                               observer.onNext(.denied)
                default:                                    observer.onNext(.notDetermined)
                }
                observer.onCompleted()
            }
            return Disposables.create()
        }
    }
}
