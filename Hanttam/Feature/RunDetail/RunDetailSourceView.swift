//
//  RunDetailSourceView.swift
//  Hanttam
//

import SwiftUI
internal import HealthKit

struct RunDetailSourceView: View {
    let record: RunningRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RunDetailContentView.SectionHeader(title: "WORKOUT INFO", icon: "info.circle")

                infoCard(title: "운동 정보") {
                    InfoRow(label: "유형", value: record.isIndoor ? "실내 러닝" : "실외 러닝")
                }

                infoCard(title: "데이터 수집 앱") {
                    InfoRow(label: "이름", value: record.sourceName)
                    if let bundleId = record.workout?.sourceRevision.source.bundleIdentifier {
                        Divider()
                        InfoRow(label: "Bundle ID", value: bundleId)
                    }
                    if let version = record.workout?.sourceRevision.version {
                        Divider()
                        InfoRow(label: "버전", value: version)
                    }
                }

                if let device = record.workout?.device {
                    infoCard(title: "데이터 수집 기기") {
                        InfoRow(label: "이름",   value: device.name         ?? "알 수 없음")
                        Divider()
                        InfoRow(label: "모델",   value: device.model        ?? "알 수 없음")
                        Divider()
                        InfoRow(label: "제조사", value: device.manufacturer ?? "알 수 없음")
                        if let hw = device.hardwareVersion { Divider(); InfoRow(label: "하드웨어", value: hw) }
                        if let sw = device.softwareVersion { Divider(); InfoRow(label: "소프트웨어", value: sw) }
                    }
                }
            }
            .padding(.horizontal, RunDetailLayout.horizontalInset)
            .padding(.top, RunDetailLayout.topInset)
            .padding(.bottom, RunDetailLayout.bottomInset)
        }
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.captionMD.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RunDetailLayout.cardRadius))
    }

    struct InfoRow: View {
        let label: String
        let value: String
        var body: some View {
            HStack {
                Text(label).font(AppFont.bodySM).foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text(value).font(AppFont.bodySM.weight(.medium)).foregroundStyle(AppColor.textPrimary)
            }
            .padding(.vertical, 8)
        }
    }
}
