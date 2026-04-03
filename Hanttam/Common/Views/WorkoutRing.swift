//
//  WorkoutRing.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//
import SwiftUI

struct WorkoutRingData: Hashable {
    let label: String
    let color: Color
    let progress: Double  // 0.0 ~ 1.0+

    static let defaultRings: [WorkoutRingData] = [
        .init(label: "옐로",   color: AppColor.yellow,  progress: 1.0),
        .init(label: "오렌지", color: AppColor.orange,  progress: 1.0),
        .init(label: "그린",   color: AppColor.green,   progress: 1.0),
        .init(label: "블루",   color: AppColor.blue,    progress: 1.0),
        .init(label: "퍼플",   color: AppColor.purple,  progress: 1.0),
        .init(label: "블랙",   color: AppColor.black,   progress: 1.0),
        .init(label: "볼트",   color: AppColor.volt,    progress: 1.0),
    ]
}

struct WorkoutRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let scale = size / 280.0

        let centerSize = 198.0 * scale
        let holeX = (size - centerSize) / 2
        let holeY = 18.0 * scale

        var path = Path()
        path.addEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        path.addEllipse(in: CGRect(x: holeX, y: holeY, width: centerSize, height: centerSize))

        return path
    }
}

// MARK: - Single Ring View (Original)

struct WorkoutRingView: View {
    var progress: Double = 1.0
    var color: Color = AppColor.backgroundRing
    var additive: Bool = false

    var body: some View {
        RippleRingShape(outerDiameter: 102, innerDiameter: 50, holeOffset: 20)
            .fill(color, style: FillStyle(eoFill: true))
            .mask {
                if progress >= 1.0 {
                    Rectangle()
                } else {
                    AngularGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: progress),
                            .init(color: .clear, location: progress),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        angle: .degrees(-90)
                    )
                }
            }
            .blendMode(additive ? .plusLighter : .normal)
    }
}

// MARK: - Ripple Ring Shape

/// 각 링의 중심이 위쪽으로 조금씩 어긋나도록 설계된 링 Shape
struct RippleRingShape: Shape {
    let outerDiameter: CGFloat
    let innerDiameter: CGFloat
    let holeOffset: CGFloat  // 안쪽 원(구멍)의 수직 오프셋 (양수 = 위로)

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let outerR = outerDiameter / 2
        let innerR = innerDiameter / 2

        var path = Path()

        // 8:2 비율: 높이 = 너비 / 4
        let outerH = outerDiameter / 3
        let innerH = innerDiameter / 4

        guard holeOffset > 0 else {
            // holeOffset == 0: 동심 링 유지
            path.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerH / 2,
                                        width: outerDiameter, height: outerH))
            path.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerH / 2,
                                        width: innerDiameter, height: innerH))
            return path
        }

        // 아래 타원(outer): 펀치홀이 뚫린 링
        // 홀 = innerDiameter + 2*holeOffset (위 타원보다 약간 크게, 같은 8:2 비율)
        let holeDiameter = innerDiameter + 2 * holeOffset
        let holeR = holeDiameter / 2
        let holeH = holeDiameter / 4  // 8:2 비율 유지

        // 세 타원 모두 x 축 중심 동일 (cx), y 축 중심도 동일 (cy)
        // 1. 아래 타원 외곽
        path.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerH / 2,
                                    width: outerDiameter, height: outerH))
        // 2. 펀치홀 (eoFill count 2 → 비어 있음)
        path.addEllipse(in: CGRect(x: cx - holeR+15, y: cy - holeH / 2 + 4,
                                    width: holeDiameter-30, height: holeH-8))
        // 3. 위 타원 솔리드 (eoFill count 3 → 다시 채워짐, 펀치홀 없음)
        path.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerH / 2 - 5,
                                    width: innerDiameter, height: innerH))

        return path
    }
}

// MARK: - Multi Ring View (Ripples style)

struct WorkoutMultiRingView: View {
    var rings: [WorkoutRingData]
    var size: CGFloat = 280

    /// 링의 두께 (지름의 일정 비율)
    private let thicknessRatio: CGFloat = 0.065
    /// 링 사이의 간격 비율
    private let gapRatio: CGFloat = 0.04
    /// 링 중심 이동 비율 (ripple 효과용 - 위쪽으로 쏠림)
    private let offsetFactor: CGFloat = 0.22

    var body: some View {
        let ringCount = min(rings.count, 7)
        let baseThickness = size * thicknessRatio
        let baseGap = size * gapRatio

        ZStack {
            // 배경
            Circle()
                .fill(AppColor.backgroundRing)
                .frame(width: size, height: size)

            // 링들 (바깥 → 안쪽 순서: 노랑, 주황, 초록, 파랑, 보라, 검정, 볼트)
            ForEach(0..<ringCount, id: \.self) { index in
                let ring = rings[index]
                
                // 각 링의 외경 계산
                let outerDiameter = size - CGFloat(index) * (baseThickness + baseGap) * 2
                let innerDiameter = outerDiameter - baseThickness * 2
                
                // 수면 파동 효과: 안쪽 링들의 중심을 위로 이동 (Y 감소)
                // "1번: Bunched at the top (Inner centers shifted UP, top gaps smaller)"
                let verticalShift = -CGFloat(index) * (baseThickness * offsetFactor)

                rippleRingLayer(
                    progress: ring.progress,
                    color: ring.color,
                    outerDiameter: outerDiameter,
                    innerDiameter: innerDiameter,
                    yOffset: verticalShift
                )
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func rippleRingLayer(
        progress: Double,
        color: Color,
        outerDiameter: CGFloat,
        innerDiameter: CGFloat,
        yOffset: CGFloat
    ) -> some View {
        let clampedProgress = min(max(progress, 0), 1)
        
        // 이 링 내부에서도 미세한 비대칭 보정을 줄 수 있음 (선택 사항)
        let internalHoleOffset: CGFloat = 0

        ZStack {
            // 배경 링 (연한 색)
            RippleRingShape(
                outerDiameter: outerDiameter,
                innerDiameter: innerDiameter,
                holeOffset: internalHoleOffset
            )
            .fill(color.opacity(0.12), style: FillStyle(eoFill: true))
            
            // 진행도 표시 링
            RippleRingShape(
                outerDiameter: outerDiameter,
                innerDiameter: innerDiameter,
                holeOffset: internalHoleOffset
            )
            .fill(color, style: FillStyle(eoFill: true))
            .mask {
                if clampedProgress >= 1.0 {
                    Rectangle()
                } else {
                    AngularGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: clampedProgress),
                            .init(color: .clear, location: clampedProgress),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        angle: .degrees(-90)
                    )
                }
            }
        }
        .offset(y: yOffset)
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

// #Preview("Workout Multi Ring") {
//     VStack(spacing: 40) {
//         WorkoutMultiRingView(
//             rings: WorkoutRingData.defaultRings,
//             size: 280
//         )
//
//         WorkoutMultiRingView(
//             rings: [
//                 .init(label: "옐로",   color: .yellow,  progress: 1.0),
//                 .init(label: "오렌지", color: .orange,   progress: 0.8),
//                 .init(label: "그린",   color: .green,    progress: 0.6),
//                 .init(label: "블루",   color: .blue,     progress: 0.4),
//                 .init(label: "퍼플",   color: .purple,   progress: 0.2),
//             ],
//             size: 200
//         )
//     }
//     .padding()
// }
