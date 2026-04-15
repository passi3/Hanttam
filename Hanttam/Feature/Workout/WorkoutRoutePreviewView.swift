//
//  WorkoutRoutePreviewView.swift
//  Hanttam
//

import UIKit
import MapKit

final class WorkoutRoutePreviewView: UIView {
    private let coordinates: [CLLocationCoordinate2D]
    private let accentColor: UIColor
    private let glowLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let dotLayer  = CAShapeLayer()

    init(coordinates: [CLLocationCoordinate2D], accentColor: UIColor) {
        self.coordinates = coordinates
        self.accentColor = accentColor
        super.init(frame: .zero)
        backgroundColor = AppColor.UI.backgroundSecondary
        layer.cornerRadius = 22
        layer.masksToBounds = true

        glowLayer.strokeColor = accentColor.withAlphaComponent(0.18).cgColor
        glowLayer.fillColor   = UIColor.clear.cgColor
        glowLayer.lineWidth   = 10
        glowLayer.lineCap     = .round
        glowLayer.lineJoin    = .round
        glowLayer.shadowColor   = accentColor.cgColor
        glowLayer.shadowOpacity = 0.18
        glowLayer.shadowRadius  = 12
        glowLayer.shadowOffset  = .zero

        lineLayer.strokeColor = AppColor.UI.textPrimary.withAlphaComponent(0.78).cgColor
        lineLayer.fillColor   = UIColor.clear.cgColor
        lineLayer.lineWidth   = 3
        lineLayer.lineCap     = .round
        lineLayer.lineJoin    = .round

        dotLayer.fillColor = accentColor.cgColor

        layer.addSublayer(glowLayer)
        layer.addSublayer(lineLayer)
        layer.addSublayer(dotLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        drawRoute()
    }

    private func drawRoute() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard !coordinates.isEmpty else {
            glowLayer.path = nil; lineLayer.path = nil; dotLayer.path = nil
            return
        }

        let xs = coordinates.map(\.longitude)
        let ys = coordinates.map(\.latitude)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let width  = max(maxX - minX, 0.0001)
        let height = max(maxY - minY, 0.0001)
        let inset: CGFloat = 20
        let drawable = bounds.insetBy(dx: inset, dy: inset)

        let path = UIBezierPath()
        for (i, coord) in coordinates.enumerated() {
            let x = drawable.minX + CGFloat((coord.longitude - minX) / width) * drawable.width
            let y = drawable.maxY - CGFloat((coord.latitude  - minY) / height) * drawable.height
            let pt = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }

        glowLayer.path = path.cgPath
        lineLayer.path = path.cgPath

        if let last = path.currentPoint as CGPoint? {
            dotLayer.path = UIBezierPath(ovalIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)).cgPath
        }
    }
}
