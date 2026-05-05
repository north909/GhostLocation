import SwiftUI
import MapKit

// MARK: – Annotation types

class OriginPin: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let title: String? = "Start"
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

class DestinationPin: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let title: String? = "Destination"
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

class StaticPin: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let title: String? = "Fake location"
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

class LivePin: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let title: String? = nil
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

// MARK: – View

struct MapPickerView: NSViewRepresentable {
    @Binding var mode: TravelMode
    @Binding var pinCoord: CLLocationCoordinate2D?       // Pin mode
    @Binding var originCoord: CLLocationCoordinate2D?    // Route mode start
    @Binding var destCoord: CLLocationCoordinate2D?      // Route mode end
    var liveCoord: CLLocationCoordinate2D?               // Simulated position (read-only)
    var routePolyline: MKPolyline?                       // Overlay
    @Binding var region: MKCoordinateRegion

    var onDestinationSet: (() -> Void)?                  // callback → trigger route calc

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.setRegion(region, animated: false)
        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.tapped(_:)))
        map.addGestureRecognizer(click)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        // Sync external region changes (search)
        if abs(map.region.center.latitude  - region.center.latitude)  > 0.001 ||
           abs(map.region.center.longitude - region.center.longitude) > 0.001 {
            map.setRegion(region, animated: true)
        }

        // Rebuild annotations
        map.removeAnnotations(map.annotations)
        switch mode {
        case .pin:
            if let c = pinCoord    { map.addAnnotation(StaticPin(c)) }
        case .driving:
            if let c = originCoord { map.addAnnotation(OriginPin(c)) }
            if let c = destCoord   { map.addAnnotation(DestinationPin(c)) }
            if let c = liveCoord   { map.addAnnotation(LivePin(c)) }
        }

        // Rebuild overlays
        map.removeOverlays(map.overlays)
        if let poly = routePolyline { map.addOverlay(poly) }
    }

    // MARK: Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapPickerView

        init(_ parent: MapPickerView) { self.parent = parent }

        @objc func tapped(_ g: NSClickGestureRecognizer) {
            guard let map = g.view as? MKMapView else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)

            switch parent.mode {
            case .pin:
                parent.pinCoord = coord

            case .driving:
                if parent.originCoord == nil {
                    parent.originCoord = coord
                } else if parent.destCoord == nil {
                    parent.destCoord = coord
                    parent.onDestinationSet?()
                } else {
                    // Reset – start picking again
                    parent.originCoord = coord
                    parent.destCoord   = nil
                }
            }
        }

        // Annotation views
        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is StaticPin:
                let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "static")
                v.markerTintColor = NSColor.systemCyan
                v.glyphImage      = NSImage(systemSymbolName: "location.slash.fill",
                                            accessibilityDescription: nil)
                v.isDraggable     = true
                v.canShowCallout  = false
                return v

            case is OriginPin:
                let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "origin")
                v.markerTintColor = NSColor.systemGreen
                v.glyphText       = "A"
                v.canShowCallout  = true
                return v

            case is DestinationPin:
                let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "dest")
                v.markerTintColor = NSColor.systemRed
                v.glyphText       = "B"
                v.canShowCallout  = true
                return v

            case is LivePin:
                let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "live")
                v.markerTintColor = NSColor.systemCyan
                v.glyphImage      = NSImage(systemSymbolName: "location.fill",
                                            accessibilityDescription: nil)
                v.canShowCallout  = false
                return v

            default: return nil
            }
        }

        // Drag support for static pin
        func mapView(_ map: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState,
                     fromOldState _: MKAnnotationView.DragState) {
            if newState == .ending, let coord = view.annotation?.coordinate {
                if view.annotation is StaticPin { parent.pinCoord = coord }
            }
        }

        // Route polyline style
        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = NSColor.systemCyan.withAlphaComponent(0.7)
            r.lineWidth   = 5
            return r
        }

        func mapView(_ map: MKMapView, regionDidChangeAnimated _: Bool) {
            parent.region = map.region
        }
    }
}
