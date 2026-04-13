//
//  WorkoutMapDelegate.swift
//  Hanttam
//

import UIKit
import MapKit
import CoreLocation

// MARK: - Shared Route Update Model

struct WorkoutRouteUpdate {
    let coordinate    : CLLocationCoordinate2D
    let allCoordinates: [CLLocationCoordinate2D]
    let allHeartRates : [Double?]               // parallel to allCoordinates
    let isFirstUpdate : Bool
}

// MARK: - Heart Rate Zone Polyline

private final class ZonePolyline: MKPolyline {
    var hrZone: HRZone = .noData
}

// MARK: - Heart Rate Zone

private enum HRZone: Equatable {
    case noData, zone1, zone2, zone3, zone4, zone5
}

// MARK: - Shared Map Delegate

final class WorkoutMapDelegate: NSObject, MKMapViewDelegate {

    // MARK: - Zone helpers

    private static func zone(for bpm: Double?) -> HRZone {
        guard let bpm else { return .noData }
        switch bpm {
        case ..<114:  return .zone1
        case ..<133:  return .zone2
        case ..<152:  return .zone3
        case ..<171:  return .zone4
        default:      return .zone5
        }
    }

    private static func color(for zone: HRZone) -> UIColor {
        switch zone {
        case .noData: return AppColor.UI.workoutRoute
        case .zone1:  return .systemGray
        case .zone2:  return .systemCyan
        case .zone3:  return .systemGreen
        case .zone4:  return .systemYellow
        case .zone5:  return .systemRed
        }
    }

    private struct ZoneSegment {
        let zone: HRZone
        var coordinates: [CLLocationCoordinate2D]
    }

    private static func buildSegments(
        coordinates: [CLLocationCoordinate2D],
        heartRates : [Double?]
    ) -> [ZoneSegment] {
        guard !coordinates.isEmpty else { return [] }
        var segments: [ZoneSegment] = []
        var current = ZoneSegment(
            zone: zone(for: heartRates.first ?? nil),
            coordinates: [coordinates[0]]
        )
        for i in 1..<coordinates.count {
            let z = zone(for: i < heartRates.count ? heartRates[i] : nil)
            if z == current.zone {
                current.coordinates.append(coordinates[i])
            } else {
                current.coordinates.append(coordinates[i])  // overlap for continuity
                segments.append(current)
                current = ZoneSegment(zone: z, coordinates: [coordinates[i]])
            }
        }
        segments.append(current)
        return segments
    }

    // MARK: - Apply

    func apply(_ update: WorkoutRouteUpdate, to mapView: MKMapView) {
        if update.isFirstUpdate {
            let region = MKCoordinateRegion(
                center: update.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: false)
        } else {
            let camera = MKMapCamera(
                lookingAtCenter: update.coordinate,
                fromDistance: 500,
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: true)
        }

        mapView.removeOverlays(mapView.overlays)
        if update.allCoordinates.count >= 2 {
            let segments = WorkoutMapDelegate.buildSegments(
                coordinates: update.allCoordinates,
                heartRates : update.allHeartRates
            )
            for segment in segments where segment.coordinates.count >= 2 {
                var coords = segment.coordinates
                let polyline = ZonePolyline(coordinates: &coords, count: coords.count)
                polyline.hrZone = segment.zone
                mapView.addOverlay(polyline)
            }
        }

        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = update.coordinate
        mapView.addAnnotation(annotation)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? ZonePolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = WorkoutMapDelegate.color(for: polyline.hrZone)
            renderer.lineWidth   = 20
            return renderer
        }
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = AppColor.UI.workoutRoute
            renderer.lineWidth   = 20
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }
        let id   = "currentLocation"
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
        if view == nil {
            view = MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view?.frame = CGRect(x: 0, y: 0, width: 20, height: 20)

            let outer = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
            outer.backgroundColor    = .white
            outer.layer.cornerRadius = 10

            let inner = UIView(frame: CGRect(x: 3, y: 3, width: 14, height: 14))
            inner.layer.cornerRadius = 7
            outer.addSubview(inner)
            view?.addSubview(outer)
        } else {
            view?.annotation = annotation
        }

        // 매번 accentColor 갱신 (레벨 변경 반영)
        if let outer = view?.subviews.first,
           let inner = outer.subviews.first {
            inner.backgroundColor = RunningLevelManager.shared.accentUIColor
        }
        return view
    }
}
