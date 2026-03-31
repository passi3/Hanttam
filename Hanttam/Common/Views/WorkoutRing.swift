//
//  WorkoutRing.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//
import SwiftUI

struct RippleBaseRing: Shape {
    let outerDiameter: CGFloat
    let innerDiameter: CGFloat
    let holeOffset: CGFloat
    let heightRatio: CGFloat
    var yOffset: CGFloat

    var animatableData: CGFloat {
        get { yOffset }
        set { yOffset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let outerR = outerDiameter / 2

        var path = Path()

        let outerH = outerDiameter * heightRatio

        guard holeOffset > 0 else {
            path.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerH / 2 + yOffset,
                                        width: outerDiameter, height: outerH))
            return path
        }

        let holeDiameter = innerDiameter + 3 * holeOffset
        let holeR = holeDiameter / 2
        let holeH = holeDiameter * heightRatio

        path.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerH / 2 + yOffset,
                                    width: outerDiameter, height: outerH))
        
        // 펀치홀 추가
        path.addEllipse(in: CGRect(x: cx - holeR + 15, y: cy - holeH / 2 + 4 + yOffset,
                                    width: holeDiameter - 30, height: holeH - 8))
        
        return path
    }
}

// MARK: - 2. 위에 올려진 타원 (솔리드)
struct RippleTopEllipse: Shape {
    let innerDiameter: CGFloat
    let heightRatio: CGFloat
    var yOffset: CGFloat

    var animatableData: CGFloat {
        get { yOffset }
        set { yOffset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let innerR = innerDiameter / 2
        
        let innerH = innerDiameter * heightRatio

        var path = Path()

        path.addEllipse(in: CGRect(x: cx - innerR,
                                    y: cy - innerH / 2 + yOffset,
                                    width: innerDiameter,
                                    height: innerH))
        
        return path
    }
}

struct RippleRingView: View {
    let outerD: CGFloat = 200
    let innerD: CGFloat = 100
    let offset: CGFloat = 30
    var onAnimationComplete: (() -> Void)? = nil

    // 각 링의 원래 yOffset 값 (바깥쪽 → 안쪽 순서)
    private let originalOffsets: [CGFloat] = [1, -2, -5, -8, -11, -14, -17, -25]

    // 애니메이션용 yOffset 상태 (원래 위치에서 시작)
    @State private var animatedOffsets: [CGFloat] = [1, -2, -5, -8, -11, -14, -17, -25]
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            RippleBaseRing(outerDiameter: outerD + 100, innerDiameter: innerD + 110, holeOffset: offset, heightRatio: 0.3, yOffset: animatedOffsets[0])
                .fill(Color.yellow, style: FillStyle(eoFill: true))

            RippleBaseRing(outerDiameter: outerD + 70, innerDiameter: innerD + 80, holeOffset: offset, heightRatio: 0.3, yOffset: animatedOffsets[1])
                .fill(Color.orange, style: FillStyle(eoFill: true))

            RippleBaseRing(outerDiameter: outerD + 40, innerDiameter: innerD + 50, holeOffset: offset, heightRatio: 0.3, yOffset: animatedOffsets[2])
                .fill(Color.green, style: FillStyle(eoFill: true))

            RippleBaseRing(outerDiameter: outerD + 10, innerDiameter: innerD + 50, holeOffset: offset - 10, heightRatio: 0.3, yOffset: animatedOffsets[3])
                .fill(Color.blue, style: FillStyle(eoFill: true))

            RippleBaseRing(outerDiameter: outerD - 20, innerDiameter: innerD + 20, holeOffset: offset - 10, heightRatio: 0.3, yOffset: animatedOffsets[4])
                .fill(Color.purple, style: FillStyle(eoFill: true))

            RippleBaseRing(outerDiameter: outerD - 50, innerDiameter: innerD + 20, holeOffset: offset - 20, heightRatio: 0.3, yOffset: animatedOffsets[5])
                .fill(Color.black, style: FillStyle(eoFill: true))

            RippleBaseRing(outerDiameter: outerD - 80, innerDiameter: innerD - 10, holeOffset: offset - 20, heightRatio: 0.3, yOffset: animatedOffsets[6])
                .fill(Color.pink, style: FillStyle(eoFill: true))

            RippleTopEllipse(innerDiameter: innerD - 30, heightRatio: 0.3, yOffset: animatedOffsets[7])
                .fill(Color.cyan)
        }
        .frame(width: outerD + 60, height: 150)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            startRippleAnimation()
        }
    }

    private func startRippleAnimation() {
        let ringCount = originalOffsets.count
        let delayPerRing: Double = 0.12
        let toZeroDuration: Double = 0.25
        let returnDuration: Double = 0.35

        // 안쪽(인덱스 큰 쪽)부터 바깥쪽으로 순차 애니메이션
        for i in 0..<ringCount {
            let reverseIndex = ringCount - 1 - i
            let delay = Double(i) * delayPerRing

            // Phase 1: 원래 위치 → 0으로
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeIn(duration: toZeroDuration)) {
                    animatedOffsets[reverseIndex] = 0
                }
            }

            // Phase 2: 0 → 원래 위치로 복귀
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + toZeroDuration) {
                withAnimation(.easeOut(duration: returnDuration)) {
                    animatedOffsets[reverseIndex] = originalOffsets[reverseIndex]
                }

                // 마지막 링 애니메이션 완료 후 콜백
                if i == ringCount - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + returnDuration) {
                        onAnimationComplete?()
                    }
                }
            }
        }
    }
}
#Preview {
    RippleRingView()
}
