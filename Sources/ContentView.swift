import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var devices = DeviceManager()
    @StateObject private var spoofer = LocationSpoofer()
    @StateObject private var router  = RouteSimulator()

    @State private var mode: TravelMode = .pin

    // Pin mode
    @State private var pinCoord: CLLocationCoordinate2D?

    // Route mode
    @State private var originCoord: CLLocationCoordinate2D?
    @State private var destCoord: CLLocationCoordinate2D?

    // Shared map state
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span:   MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
    )

    var body: some View {
        HSplitView {
            SidebarView(
                devices:     devices,
                spoofer:     spoofer,
                router:      router,
                mode:        $mode,
                pinCoord:    $pinCoord,
                originCoord: $originCoord,
                destCoord:   $destCoord
            )
            .frame(minWidth: 270, idealWidth: 290, maxWidth: 330)

            VStack(spacing: 0) {
                SearchBarView(
                    coordinate: searchBinding,
                    region:     $region
                )
                .frame(height: 38)

                MapPickerView(
                    mode:         $mode,
                    pinCoord:     $pinCoord,
                    originCoord:  $originCoord,
                    destCoord:    $destCoord,
                    liveCoord:    router.currentCoord,
                    routePolyline: router.routePolyline,
                    region:       $region,
                    onDestinationSet: fetchRoute
                )
                .overlay(alignment: .topTrailing) { mapHint }
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .preferredColorScheme(.dark)
    }

    // SearchBarView expects a Binding<CLLocationCoordinate2D?> that drops a pin
    // In route mode, searching sets the destination
    var searchBinding: Binding<CLLocationCoordinate2D?> {
        Binding(
            get: { mode == .pin ? pinCoord : destCoord },
            set: { coord in
                if mode == .pin {
                    pinCoord = coord
                } else {
                    if originCoord == nil { originCoord = coord }
                    else {
                        destCoord = coord
                        fetchRoute()
                    }
                }
            }
        )
    }

    var mapHint: some View {
        Group {
            if mode == .pin && pinCoord == nil {
                hintBadge("Click the map to place your fake location")
            } else if mode != .pin && originCoord == nil {
                hintBadge("Click A: start  →  then B: destination")
            } else if mode != .pin && destCoord == nil {
                hintBadge("Now click B: your destination")
            }
        }
    }

    func hintBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .cornerRadius(6)
            .padding(10)
    }

    func fetchRoute() {
        guard let o = originCoord, let d = destCoord, mode != .pin else { return }
        Task { await router.computeRoute(from: o, to: d, mode: mode) }
    }
}
