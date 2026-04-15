//
//  WorkoutRouteView.swift
//  Hanttam
//
//  Created by passi on 4/14/26.
//

import SwiftUI
import MapKit

struct WorkoutRouteView: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        Canvas { context, size in
            guard coordinates.count >= 2 else { return }

            let lons = coordinates.map(\.longitude)
            let lats = coordinates.map(\.latitude)
            guard let minLon = lons.min(), let maxLon = lons.max(),
                  let minLat = lats.min(), let maxLat = lats.max() else { return }

            let lonRange = max(maxLon - minLon, 0.0001)
            let latRange = max(maxLat - minLat, 0.0001)
            let inset: CGFloat = 16
            let drawable = CGRect(
                x: inset, y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )

            func point(for coord: CLLocationCoordinate2D) -> CGPoint {
                CGPoint(
                    x: drawable.minX + CGFloat((coord.longitude - minLon) / lonRange) * drawable.width,
                    y: drawable.maxY - CGFloat((coord.latitude - minLat) / latRange) * drawable.height
                )
            }

            var path = Path()
            for (i, coord) in coordinates.enumerated() {
                let pt = point(for: coord)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }

            let accent = Color(RunningLevelManager.shared.accentColor)

            // Glow
            var glowContext = context
            glowContext.addFilter(.shadow(color: accent.opacity(0.5), radius: 12, x: 0, y: 0))
            glowContext.stroke(
                path,
                with: .color(accent.opacity(0.3)),
                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
            )

            // Main line
            context.stroke(
                path,
                with: .color(.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )

            // // Start dot
            // let startPt = point(for: coordinates[0])
            // context.fill(
            //     Path(ellipseIn: CGRect(x: startPt.x - 3.5, y: startPt.y - 3.5, width: 7, height: 7)),
            //     with: .color(accent)
            // )
           
            // // End dot
            // let endPt = point(for: coordinates[coordinates.count - 1])
            // context.fill(
            //     Path(ellipseIn: CGRect(x: endPt.x - 3.5, y: endPt.y - 3.5, width: 7, height: 7)),
            //     with: .color(accent.opacity(0.8))
            // )
        }
    }
}
