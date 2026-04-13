//
//  WorkoutView.swift
//  Hanttam
//
//  Created by passi on 3/25/26.
//

import SwiftUI
import MapKit

struct WorkoutView: View {
    private enum PendingStartKind {
        case freeRun
        case intervalRun
    }

    private struct WorkoutAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

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
    @State private var freeRunWatchPrimary = false
    @State private var intervalWatchPrimary = false
    @State private var showWatchInfo = false
    @State private var watchButtonFrame: CGRect = .zero
    @State private var pendingWatchStart: PendingStartKind?
    @State private var workoutAlert: WorkoutAlert?
    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20
    @AppStorage("workoutIsIndoor") private var isIndoor: Bool = false
    @State private var position: MapCameraPosition
    private static let mapDistance: Double = 1500

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
                Annotation("", coordinate: displayCoordinate){
                    Circle()
                        .fill(RunningLevelManager.shared.accentColor)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        )
                }
            }
            .mapStyle(.standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            ))
            
            TabView(selection: $page) {
                FreeRunScreen(startAction: startFreeRun)
                    .tag(0)
                IntervalScreen(totalSets: $intervalSets, startAction: startIntervalRun)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.clear)

            // 상단: 날씨 + 페이지 인디케이터
            VStack(spacing: 6) {
                WorkoutWeatherView()

                HStack(spacing: 6) {
                    Capsule()
                        .fill(page == 0 ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: page == 0 ? 20 : 6, height: 6)
                    Capsule()
                        .fill(page == 1 ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: page == 1 ? 20 : 6, height: 6)
                }
                .animation(.spring(duration: 0.3), value: page)

                HStack(spacing: 8) {
                    indoorOutdoorToggle
                    workoutSourceButton
                }
            }
            .padding(.top, 6)
        }
        .coordinateSpace(name: "workoutView")
        .overlay {
            if showWatchInfo {
                watchConnectionOverlay
            }
        }
        .onPreferenceChange(WatchButtonFramePreferenceKey.self) { frame in
            watchButtonFrame = frame
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
        .fullScreenCover(isPresented: $showFreeRun, onDismiss: {
            freeRunWatchPrimary = false
        }) {
            FreeRunView(isIndoor: isIndoor, isWatchPrimary: freeRunWatchPrimary)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showIntervalRun, onDismiss: {
            intervalWatchPrimary = false
        }) {
            IntervalRunView(
                sets: intervalSets,
                lapDistance: lapDistance,
                restDuration: restDuration,
                isIndoor: isIndoor,
                isWatchPrimary: intervalWatchPrimary
            )
            .ignoresSafeArea()
        }
        .alert(item: $workoutAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("확인"))
            )
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
        .onReceive(NotificationCenter.default.publisher(for: WatchBridge.workoutStartedNotification)) { note in
            guard let kindRaw = note.userInfo?["kind"] as? String,
                  let kind = WatchBridge.WorkoutKind(rawValue: kindRaw) else { return }

            pendingWatchStart = nil

            switch kind {
            case .freeRun:
                freeRunWatchPrimary = true
                showFreeRun = true
            case .intervalRun:
                intervalWatchPrimary = true
                if let sets = note.userInfo?["sets"] as? Int {
                    intervalSets = sets
                }
                showIntervalRun = true
            }
        }
        .onChange(of: watchBridge.collectionState) { _, newState in
            guard case .phoneOnly = newState else { return }

            if showFreeRun || showIntervalRun {
                // 세션 화면이 이미 열린 상태에서 워치 실패 → 폰 모드로 전환
                NotificationCenter.default.post(name: WatchBridge.watchFailedFallbackNotification, object: nil)
            } else if let pending = pendingWatchStart {
                // 화면이 열리기 전 워치 요청 실패 → 폰 직접 시작
                pendingWatchStart = nil
                switch pending {
                case .freeRun:    startPhoneFreeRun()
                case .intervalRun: startPhoneIntervalRun()
                }
            }
        }
    }
    
    private var indoorOutdoorToggle: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { isIndoor.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isIndoor ? "figure.run.treadmill" : "figure.run")
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

    private var workoutSourceButton: some View {
        Button {
            guard watchBridge.canStartWorkoutOnWatch else { return }
            withAnimation(.spring(duration: 0.25)) {
                showWatchInfo = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: watchBridge.canStartWorkoutOnWatch ? "applewatch" : "iphone")
                    .font(.system(size: 20, weight: .semibold))
                Text(watchBridge.canStartWorkoutOnWatch ? "워치" : "아이폰")
                    .font(AppFont.labelSM)
                    .tracking(1)
            }
            .foregroundStyle(watchBridge.canStartWorkoutOnWatch ? AppColor.success : AppColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColor.cardBackground.opacity(0.94), in: Capsule())
            .opacity(watchBridge.canStartWorkoutOnWatch ? 1 : 0.72)
        }
        .disabled(!watchBridge.canStartWorkoutOnWatch)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: WatchButtonFramePreferenceKey.self,
                        value: proxy.frame(in: .named("workoutView"))
                    )
            }
        }
    }

    private var watchConnectionOverlay: some View {
        GeometryReader { proxy in
            let cardWidth = min(280.0, proxy.size.width - 32)
            let minX = 16.0 + cardWidth / 2
            let maxX = proxy.size.width - 16.0 - cardWidth / 2
            let desiredX = watchButtonFrame.maxX - cardWidth / 2
            let cardCenterX = min(max(desiredX, minX), maxX)
            let cardTop = watchButtonFrame.maxY + 10

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showWatchInfo = false
                        }
                    }

                WatchConnectionSheet(info: watchBridge.watchConnectionInfo)
                    .frame(width: cardWidth)
                    .position(x: cardCenterX, y: cardTop + 78)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }

    private func startFreeRun() {
        requestHealthAuthorization {
            if watchBridge.canStartWorkoutOnWatch {
                let accepted = watchBridge.requestWorkoutStartOnWatch(kind: .freeRun)
                if accepted {
                    // 워치로 요청 전송 성공 → 즉시 세션 화면 표시
                    freeRunWatchPrimary = true
                    showFreeRun = true
                } else {
                    startPhoneFreeRun()
                }
            } else {
                startPhoneFreeRun()
            }
        }
    }

    private func startIntervalRun() {
        guard intervalSets > 0 else {
            workoutAlert = WorkoutAlert(title: "세트를 설정하세요", message: "인터벌 운동을 시작하려면 세트 수를 먼저 정해주세요.")
            return
        }

        requestHealthAuthorization {
            if watchBridge.canStartWorkoutOnWatch {
                let accepted = watchBridge.requestWorkoutStartOnWatch(
                    kind: .intervalRun,
                    payload: [
                        "sets": intervalSets,
                        "lapDistance": lapDistance,
                        "restDuration": restDuration
                    ]
                )
                if accepted {
                    // 워치로 요청 전송 성공 → 즉시 세션 화면 표시
                    intervalWatchPrimary = true
                    showIntervalRun = true
                } else {
                    startPhoneIntervalRun()
                }
            } else {
                startPhoneIntervalRun()
            }
        }
    }

    private func startPhoneFreeRun() {
        freeRunWatchPrimary = false
        showFreeRun = true
    }

    private func startPhoneIntervalRun() {
        intervalWatchPrimary = false
        showIntervalRun = true
    }

    private func requestHealthAuthorization(onAuthorized: @escaping () -> Void) {
        HealthKitStore.shared.requestAuthorization { ok in
            if ok {
                onAuthorized()
            } else {
                workoutAlert = WorkoutAlert(
                    title: "건강 권한 필요",
                    message: "운동을 시작하려면 건강 데이터 읽기 및 쓰기 권한이 필요합니다."
                )
            }
        }
    }
}

private struct WatchButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct WatchConnectionSheet: View {
    let info: WatchBridge.WatchConnectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("연결된 기기")
                .font(AppFont.labelSM)
                .foregroundStyle(AppColor.textSecondary)

            HStack(spacing: 14) {
                Image(systemName: "applewatch")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 52, height: 52)
                    .background(AppColor.backgroundPrimary.opacity(0.7), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(deviceTitle)
                        .font(AppFont.titleSM)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(deviceStatus)
                        .font(AppFont.labelSM)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppColor.cardBackground.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        )
    }

    private var deviceTitle: String {
        (info.isPaired && info.isAppInstalled) ? "Apple Watch" : "워치 없음"
    }

    private var deviceStatus: String {
        if info.isPaired && info.isAppInstalled && info.isReachable {
            return "지금 바로 워치에서 시작할 수 있어요"
        }
        if info.isPaired && info.isAppInstalled {
            return "워치와 연결되어 있어요"
        }
        if info.isPaired {
            return "워치 앱 설치를 확인해주세요"
        }
        return "페어링된 워치를 찾지 못했어요"
    }

    private var iconTint: Color {
        (info.isPaired && info.isAppInstalled) ? AppColor.success : AppColor.textSecondary
    }
}

#Preview {
    WorkoutView()
}
