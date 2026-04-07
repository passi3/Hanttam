//
//  ChartPlotBorderStyle.swift
//  Hanttam
//
//  Created by Codex on 4/7/26.
//

import SwiftUI
import Charts

extension View {
    func chartPlotBorderStyle(
        borderColor: Color,
        lineWidth: CGFloat = 1,
        cornerRadius: CGFloat = 0
    ) -> some View {
        chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
                .overlay {
                    if cornerRadius > 0 {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: lineWidth)
                    } else {
                        Rectangle()
                            .stroke(borderColor, lineWidth: lineWidth)
                    }
                }
        }
    }
}
