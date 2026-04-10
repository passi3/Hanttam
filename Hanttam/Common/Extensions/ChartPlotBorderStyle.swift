//
//  ChartPlotBorderStyle.swift
//  Hanttam
//
//  Created by passi on 4/7/26.
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
                .clipShape(PlotBorderShape(cornerRadius: cornerRadius))
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

private struct PlotBorderShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        if cornerRadius > 0 {
            return RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
        } else {
            return Rectangle().path(in: rect)
        }
    }
}
