//
//  SatelliteMapView.swift
//  FogLiner
//
//  Created by Albert Morris on 7/3/26.
//

import MapKit
import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
typealias PlatformTapGestureRecognizer = UITapGestureRecognizer
#else
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
typealias PlatformTapGestureRecognizer = NSClickGestureRecognizer
#endif

/// Satellite `MKMapView` base with tap-to-coordinate reporting.
///
/// SwiftUI's native `Map` can't host a custom georeferenced overlay renderer
/// (needed for the fog-of-war overlay later), so the map base is a raw
/// `MKMapView` wrapped in a platform representable, per the architecture wall.
struct SatelliteMapView: PlatformViewRepresentable {
    /// The point most recently tapped, shown as a pin with an elevation callout.
    @Binding var selectedPoint: SelectedPoint?
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    #if os(iOS)
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.mapType = .satellite
        mapView.delegate = context.coordinator
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.sync(mapView: mapView, selectedPoint: selectedPoint)
    }
    #else
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.mapType = .satellite
        mapView.delegate = context.coordinator
        let click = NSClickGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(click)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.sync(mapView: mapView, selectedPoint: selectedPoint)
    }
    #endif

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: SatelliteMapView
        private var annotation: MKPointAnnotation?

        init(_ parent: SatelliteMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let identifier = "elevationPin"
            let view =
                mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true
            return view
        }

        @objc func handleTap(_ gesture: PlatformTapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(coordinate)
        }

        /// Reconciles the single pin annotation with the current selected point,
        /// including live-updating its callout title as sampling progresses.
        func sync(mapView: MKMapView, selectedPoint: SelectedPoint?) {
            guard let selectedPoint else {
                if let annotation {
                    mapView.removeAnnotation(annotation)
                    self.annotation = nil
                }
                return
            }

            let title = selectedPoint.calloutTitle
            if let annotation {
                if annotation.coordinate.latitude != selectedPoint.coordinate.latitude
                    || annotation.coordinate.longitude != selectedPoint.coordinate.longitude
                {
                    annotation.coordinate = selectedPoint.coordinate
                }
                if annotation.title != title {
                    annotation.title = title
                }
            } else {
                let newAnnotation = MKPointAnnotation()
                newAnnotation.coordinate = selectedPoint.coordinate
                newAnnotation.title = title
                mapView.addAnnotation(newAnnotation)
                mapView.selectAnnotation(newAnnotation, animated: true)
                annotation = newAnnotation
            }
        }
    }
}

/// A tapped map point and its (possibly still-loading) sampled elevation.
struct SelectedPoint {
    let coordinate: CLLocationCoordinate2D
    var elevationMeters: Double?
    var errorMessage: String?

    var calloutTitle: String {
        if let errorMessage {
            return errorMessage
        }
        guard let elevationMeters else {
            return "Sampling elevation…"
        }
        let feet = elevationMeters * 3.28084
        return String(format: "%.0f m (%.0f ft)", elevationMeters, feet)
    }
}
