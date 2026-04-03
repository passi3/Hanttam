//
//  WorkoutView.swift
//  Hanttam
//
//  Created by passi on 3/25/26.
//

import SwiftUI
import MapKit

struct WorkoutView: View {

    private static let fallbackCoordinate = CLLocationCoordinate2D(
        latitude: 37.653,
        longitude: 127.047
    )

    @ObservedObject private var location = LocationService.shared
    @ObservedObject private var watchBridge = WatchBridge.shared
    @State private var page = 0
    @State private var showFreeRun = false
    @State private var showIntervalRun = false
    @State private var intervalSets: Int = 0
    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20
    @AppStorage("workoutIsIndoor") private var isIndoor: Bool = false
    @State private var position: MapCameraPosition
    private static let mapDistance: Double = 800

    private var isRunning: Bool { showFreeRun || showIntervalRun }

    init() {
        // 페이지 TabView 내부 UIScrollView 배경을 투명하게
        UIScrollView.appearance().backgroundColor = .clear

        // 현재 위치가 있으면 바로 사용, 없으면 fallback
        let coord = LocationService.shared.userLocation ?? Self.fallbackCoordinate
        _position = State(initialValue: .camera(
            MapCamera(centerCoordinate: coord, distance: Self.mapDistance, heading: 0, pitch: 0)
        ))
    }

    private var displayCoordinate: CLLocationCoordinate2D {
        location.userLocation ?? Self.fallbackCoordinate
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, interactionModes: []) {
                Marker("", coordinate: displayCoordinate)
                    .tint(AppColor.workoutRoute)
            }
            .mapStyle(.standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            ))

            TabView(selection: $page) {
                FreeRunScreen(showFreeRun: $showFreeRun)
                    .tag(0)
                IntervalScreen(totalSets: $intervalSets, showIntervalRun: $showIntervalRun)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.clear)

            // 상단: 날씨 + 페이지 인디케이터
            VStack(spacing: 6) {
                WorkoutWeatherView()
                watchCollectionBanner

                HStack(spacing: 6) {
                    Capsule()
                        .fill(page == 0 ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: page == 0 ? 20 : 6, height: 6)
                    Capsule()
                        .fill(page == 1 ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: page == 1 ? 20 : 6, height: 6)
                }
                .animation(.spring(duration: 0.3), value: page)

                indoorOutdoorToggle
            }
            .padding(.top, 6)
        }
        .fullScreenCover(isPresented: $showFreeRun) {
            FreeRunView(isIndoor: isIndoor, isWatchPrimary: isWatchPrimary(kind: .freeRun))
        }
        .fullScreenCover(isPresented: $showIntervalRun) {
            IntervalRunView(
                sets: intervalSets,
                lapDistance: lapDistance,
                restDuration: restDuration,
                isIndoor: isIndoor,
                isWatchPrimary: isWatchPrimary(kind: .intervalRun)
            )
        }
        .onAppear {
            LocationService.shared.startPeriodicUpdates(interval: 1.0)
            if let coord = location.userLocation {
                Task {
                    await WeatherKitManager.shared.fetch(for: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                }
            }
        }
        .onDisappear {
            LocationService.shared.stopPeriodicUpdates()
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutStartedNotification)) { note in
            guard let kindRaw = note.userInfo?["kind"] as? String,
                  let kind = WatchBridge.WorkoutKind(rawValue: kindRaw) else { return }
            switch kind {
            case .freeRun:
                showFreeRun = true
            case .intervalRun:
                showIntervalRun = true
            }
        }
        .onChange(of: location.locationUpdated) { _, _ in
            guard !isRunning else { return }
            guard let coord = location.userLocation else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                position = .camera(
                    MapCamera(centerCoordinate: coord, distance: Self.mapDistance, heading: 0, pitch: 0)
                )
            }
            Task {
                await WeatherKitManager.shared.fetch(for: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            }
        }
    }

    @ViewBuilder
    private var watchCollectionBanner: some View {
        switch watchBridge.collectionState {
        case .idle:
            EmptyView()
        case .requesting(let kind):
            workoutBanner(
                icon: "applewatch.radiowaves.left.and.right",
                text: kind == .freeRun ? "Apple Watch에서 운동 시작 준비 중" : "Apple Watch에서 인터벌 준비 중",
                tint: AppColor.warning
            )
        case .collectingOnWatch(let kind):
            workoutBanner(
                icon: "applewatch",
                text: kind == .freeRun ? "Apple Watch에서 센서 측정 중" : "Apple Watch에서 인터벌 측정 중",
                tint: AppColor.success
            )
        case .phoneOnly:
            workoutBanner(
                icon: "iphone",
                text: "Apple Watch 연결이 없어 iPhone으로 측정 중",
                tint: AppColor.textSecondary
            )
        }
    }

    private func workoutBanner(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.labelSM)
            Text(text)
                .font(AppFont.labelSM)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppColor.cardBackground.opacity(0.94), in: Capsule())
    }
    
    private var indoorOutdoorToggle: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { isIndoor.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isIndoor ? "building.2" : "figure.run")
                    .font(.system(size: 20, weight: .semibold))
                Text(isIndoor ? "실내" : "실외")
                    .font(AppFont.labelSM)
                    .tracking(1)
            }
            .foregroundStyle(isIndoor ? AppColor.warning : AppColor.success)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColor.cardBackground.opacity(0.94), in: Capsule())
        }
    }

    private func isWatchPrimary(kind: WatchBridge.WorkoutKind) -> Bool {
        switch watchBridge.collectionState {
        case .requesting(let currentKind), .collectingOnWatch(let currentKind):
            return currentKind == kind
        default:
            return false
        }
    }
}

#Preview {
    WorkoutView()
}
