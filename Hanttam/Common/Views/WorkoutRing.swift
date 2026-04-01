//
//  WorkoutRing.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//
import SwiftUI

// MARK: - 1. 배경 링 (구멍 뚫린 타원)
struct OriginRippleBaseRing: Shape {
    let outerDiameter: CGFloat
    let innerDiameter: CGFloat
    let holeOffset: CGFloat
    let heightRatio: CGFloat
    var yOffset: CGFloat

    // 사용되지 않던 animatableData 제거 완료

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
        path.addEllipse(in: CGRect(x: cx - holeR + 15, y: cy - holeH / 2 + 6 + yOffset,
                                    width: holeDiameter - 30, height: holeH - 10))
        
        return path
    }
}

// MARK: - 2. 위에 올려진 타원 (솔리드)
struct OriginRippleTopEllipse: Shape {
    let innerDiameter: CGFloat
    let heightRatio: CGFloat
    var yOffset: CGFloat

    // 사용되지 않던 animatableData 제거 완료

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

// MARK: - 메인 뷰
struct OriginRippleRingView: View {
    let outerD: CGFloat = 220
    let innerD: CGFloat = 100
    let offset: CGFloat = 30

    // 불필요한 애니메이션 변수(animatedOffsets 등), onAppear, DispatchQueue 로직 모두 제거 완료

    var body: some View {
        ZStack {
            OriginRippleBaseRing(outerDiameter: outerD - 80, innerDiameter: innerD - 10, holeOffset: offset - 24, heightRatio: 0.3, yOffset: -17)
                .stroke(.white, lineWidth: 2)
                .fill(Color(red: 151/255, green: 42/255, blue: 0), style: FillStyle(eoFill: true))

            OriginRippleTopEllipse(innerDiameter: innerD - 30, heightRatio: 0.3, yOffset: -22)
                .fill(Color(red: 240/255, green: 240/255, blue: 245/255))
        }
        .frame(width: outerD + 60, height: 150)
    }
}

#Preview {
    OriginRippleRingView()
}
