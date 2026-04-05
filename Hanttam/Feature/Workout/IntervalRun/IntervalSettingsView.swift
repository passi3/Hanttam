//
//  IntervalSettingsView.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import SwiftUI

struct IntervalSettingsView: View {

    @AppStorage("intervalLapDistance") private var lapDistance: Double = 400
    @AppStorage("intervalRestDuration") private var restDuration: Double = 20

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var levelManager = RunningLevelManager.shared

    private let distancePresets: [Double] = [200, 400, 800, 1000, 1600]

    var body: some View {
        NavigationView {
            List {
                // 랩 거리
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(distancePresets, id: \.self) { d in
                                Button {
                                    lapDistance = d
                                } label: {
                                    Text(distanceLabel(d))
                                        .font(.system(size: 15, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            lapDistance == d
                                                ? levelManager.accentColor.opacity(0.15)
                                                : Color(AppColor.UI.tertiarySystemFill)
                                        )
                                        .foregroundStyle(lapDistance == d ? levelManager.accentColor : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("랩 거리")
                }

                // 쉬는 시간
                Section {
                    Stepper("쉬는 시간: \(Int(restDuration))초", value: $restDuration, in: 5...120, step: 5)
                } header: {
                    Text("휴식")
                }
            }
            .navigationTitle("인터벌 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(levelManager.accentColor)
                }
            }
        }
    }

    private func distanceLabel(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.0fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }
}
