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
    let isFirstUpdate : Bool
}

// MARK: - Shared Map Delegate

final class WorkoutMapDelegate: NSObject, MKMapViewDelegate {

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
            var coords = update.allCoordinates
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            mapView.addOverlay(polyline)
        }

        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = update.coordinate
        mapView.addAnnotation(annotation)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
        if view == nil {
            view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        } else {
            view?.annotation = annotation
        }
        view?.markerTintColor = RunningLevelManager.shared.accentUIColor
        view?.glyphText       = ""
        return view
    }
}
