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
    @State private var page = 0
    @State private var position: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: fallbackCoordinate,
            distance: 800,
            heading: 0,
            pitch: 0
        )
    )
    
    init() {
        UIScrollView.appearance().backgroundColor = .clear
    }
    
    private var displayCoordinate: CLLocationCoordinate2D {
        location.userLocation ?? Self.fallbackCoordinate
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, interactionModes: []) {
                Marker("내 위치", coordinate: displayCoordinate)
            }
            .mapStyle(.standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            ))

            TabView(selection: $page) {
                FreeRunScreen()
                    .tag(0)
                IntervalScreen()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.clear)

            // 페이지 인디케이터
            HStack(spacing: 6) {
                Capsule()
                    .fill(page == 0 ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: page == 0 ? 20 : 6, height: 6)
                Capsule()
                    .fill(page == 1 ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: page == 1 ? 20 : 6, height: 6)
            }
            .animation(.spring(duration: 0.3), value: page)
            .padding(.top, 16)
        }
        .onAppear {
            LocationService.shared.startPeriodicUpdates(interval: 0.5)
            if let coord = location.userLocation {
                position = .camera(
                    MapCamera(centerCoordinate: coord, distance: 800, heading: 0, pitch: 0)
                )
            }
        }
        .onDisappear {
            LocationService.shared.stopPeriodicUpdates()
        }
        .onChange(of: location.locationUpdated) { _, _ in
            guard let coord = location.userLocation else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                position = .camera(
                    MapCamera(centerCoordinate: coord, distance: 800, heading: 0, pitch: 0)
                )
            }
        }
    }
}

#Preview {
    WorkoutView()
}
