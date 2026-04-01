//
//  HanttamRing.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import SwiftUI

// MARK: - 특정 위치와 크기만큼 구멍이 뚫린 큰 원 Shape
struct PunchedBigCircle: Shape {
    var holeSize: CGFloat
    var holeOffsetY: CGFloat

    var animatableData: CGFloat {
        get { holeOffsetY }
        set { holeOffsetY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.addEllipse(in: rect)

        let cx = rect.midX
        let cy = rect.midY
        let holeR = holeSize / 2

        let holeRect = CGRect(x: cx - holeR,
                              y: cy - holeR + holeOffsetY,
                              width: holeSize,
                              height: holeSize)

        path.addEllipse(in: holeRect)

        return path
    }
}

// MARK: - 메인 뷰
struct HanttamCirclesView: View {
    var topCircleOffsetY: CGFloat = -25
    
    var body: some View {
        PunchedBigCircle(holeSize: 130, holeOffsetY: topCircleOffsetY)
            .fill(Color(red: 151/255, green: 42/255, blue: 0), style: FillStyle(eoFill: true))
            .frame(width: 200, height: 200)
    }
}

// MARK: - 미리보기
#Preview {
    HanttamCirclesView(topCircleOffsetY: -25)
}
