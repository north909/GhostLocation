import Foundation
import MapKit
import CoreLocation

@MainActor
class RouteSimulator: ObservableObject {
    @Published var routePolyline: MKPolyline?
    @Published var currentCoord: CLLocationCoordinate2D?
    @Published var isRunning    = false
    @Published var isLoading    = false
    @Published var progress: Double = 0
    @Published var status       = ""
    @Published var speedMPH: Double = 80

    private var routeCoords: [CLLocationCoordinate2D] = []
    private var cumDist: [Double] = []
    private var totalDistance: Double = 0
    private var simulationTask: Task<Void, Never>?
    private var playProcess: Process?

    // MARK: Route calculation

    func computeRoute(from origin: CLLocationCoordinate2D,
                      to destination: CLLocationCoordinate2D,
                      mode: TravelMode) async -> Bool {
        isLoading = true
        status    = "Calculating route…"
        routePolyline = nil
        routeCoords   = []
        cumDist       = []

        let req = MKDirections.Request()
        req.source        = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        req.destination   = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        req.transportType = mode.transportType

        do {
            let resp = try await MKDirections(request: req).calculate()
            guard let route = resp.routes.first else {
                status = "No route found"; isLoading = false; return false
            }

            let count = route.polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: .init(), count: count)
            route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))

            routeCoords   = coords
            routePolyline = route.polyline
            totalDistance = route.distance

            var cd: [Double] = [0]
            for i in 1..<coords.count {
                cd.append(cd[i - 1] + dist(coords[i - 1], coords[i]))
            }
            cumDist = cd

            let eta = route.expectedTravelTime
            status  = "\(formatDist(totalDistance)) · ETA \(formatTime(eta))"
            isLoading = false
            return true
        } catch {
            status = "Route error: \(error.localizedDescription)"; isLoading = false; return false
        }
    }

    // MARK: Simulation — GPX playback (one persistent DVT connection)

    func start(udid: String?, rsdHost: String = "", rsdPort: String = "") {
        guard !routeCoords.isEmpty else { return }
        stop()

        let host    = rsdHost.trimmingCharacters(in: .whitespaces)
        let port    = Int(rsdPort.trimmingCharacters(in: .whitespaces)) ?? 0
        let usePymd = !host.isEmpty && port > 0
        let mps     = speedMPH * 0.44704
        let total   = totalDistance
        let expectedDuration = total / mps   // seconds

        // Write GPX to /tmp
        let gpxPath = "/tmp/ghost_route.gpx"
        let gpx = buildGPX(speedMPS: mps)
        try? gpx.write(toFile: gpxPath, atomically: true, encoding: .utf8)

        isRunning    = true
        progress     = 0
        currentCoord = routeCoords.first

        if usePymd {
            // Single long-running process — one DVT connection for the entire route
            let toolPaths = "/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/Users/\(NSUserName())/Library/Python/3.9/bin:/Users/\(NSUserName())/Library/Python/3.11/bin:/Users/\(NSUserName())/Library/Python/3.12/bin"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments     = ["-c", "pymobiledevice3 developer dvt simulate-location play --rsd \(host) \(port) \(gpxPath) 2>&1"]
            proc.environment   = ProcessInfo.processInfo.environment.merging(["PATH": toolPaths]) { _, new in new }
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError  = FileHandle.nullDevice
            try? proc.run()
            playProcess = proc
        } else {
            // Legacy idevicesetlocation fallback — pipe coords one at a time
            let uid = udid
            simulationTask = Task {
                var distTraveled: Double = 0
                while distTraveled < total && !Task.isCancelled {
                    let tickStart = Date()
                    if let coord = coordAt(distTraveled) {
                        currentCoord = coord
                        let lat = coord.latitude, lon = coord.longitude
                        await Task.detached(priority: .userInitiated) {
                            var cmd = "idevicesetlocation"
                            if let u = uid { cmd += " -u \(u)" }
                            cmd += " -- \(lat) \(lon)"
                            shell(cmd)
                        }.value
                    }
                    let elapsed  = max(Date().timeIntervalSince(tickStart), 0.5)
                    distTraveled = min(distTraveled + mps * elapsed, total)
                    progress     = distTraveled / total
                }
                isRunning = false; progress = 1.0; status = "Arrived!"
            }
            return
        }

        // Progress tracking for GPX playback
        let startTime = Date()
        simulationTask = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let p = min(elapsed / expectedDuration, 1.0)
                progress = p
                if let coord = coordAt(total * p) { currentCoord = coord }

                if p >= 1.0 {
                    playProcess?.terminate(); playProcess = nil
                    isRunning = false; status = "Arrived!"
                    break
                }
                // Check if the process ended early (error / cleared)
                if let proc = playProcess, !proc.isRunning {
                    isRunning = false; playProcess = nil; break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func stop() {
        simulationTask?.cancel(); simulationTask = nil
        playProcess?.terminate();  playProcess  = nil
        isRunning = false
        progress  = 0
    }

    // MARK: GPX generation

    private func buildGPX(speedMPS: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let base = Date(timeIntervalSince1970: 1577836800) // 2020-01-01T00:00:00Z

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<gpx version=\"1.1\" creator=\"GhostLocation\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        xml += "  <trk><trkseg>\n"

        for (i, coord) in routeCoords.enumerated() {
            let t       = cumDist[i] / max(speedMPS, 0.1)
            let ts      = formatter.string(from: base.addingTimeInterval(t))
            xml += "    <trkpt lat=\"\(coord.latitude)\" lon=\"\(coord.longitude)\">"
            xml += "<time>\(ts)</time></trkpt>\n"
        }

        xml += "  </trkseg></trk>\n</gpx>"
        return xml
    }

    // MARK: Helpers

    private func coordAt(_ targetDist: Double) -> CLLocationCoordinate2D? {
        guard cumDist.count > 1 else { return routeCoords.first }
        let clamped = min(max(targetDist, 0), cumDist.last!)
        var lo = 0, hi = cumDist.count - 2
        while lo < hi {
            let mid = (lo + hi) / 2
            cumDist[mid + 1] < clamped ? (lo = mid + 1) : (hi = mid)
        }
        let segLen = cumDist[lo + 1] - cumDist[lo]
        let t      = segLen > 0 ? (clamped - cumDist[lo]) / segLen : 0
        let a = routeCoords[lo], b = routeCoords[lo + 1]
        return CLLocationCoordinate2D(
            latitude:  a.latitude  + (b.latitude  - a.latitude)  * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    private func dist(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func formatDist(_ m: Double) -> String {
        m < 1000 ? "\(Int(m)) m" : String(format: "%.1f km", m / 1000)
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let m = Int(s) / 60
        return m < 60 ? "\(m) min" : String(format: "%dh %02dm", m / 60, m % 60)
    }
}
