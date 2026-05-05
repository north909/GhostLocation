import Foundation
import CoreLocation

@MainActor
class LocationSpoofer: ObservableObject {
    @Published var isActive       = false
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var status         = "Ready"
    @Published var errorMsg: String?
    @Published var needsTunnel    = false   // iOS 17+: show tunnel UI
    @Published var tunnelRunning  = false

    @Published var rsdHost = ""   // user pastes from tunnel terminal
    @Published var rsdPort = ""

    private var keepAlive: Task<Void, Never>?
    private var usePymd  = false
    private var activeRSDHost = ""
    private var activeRSDPort = 0

    // MARK: Public API

    func start(lat: Double, lon: Double, udid: String?) async {
        stop()
        status    = "Connecting…"
        errorMsg  = nil
        needsTunnel = false

        // Try legacy idevicesetlocation first
        let r1 = await run("idevicesetlocation", udid: udid, args: ["--", "\(lat)", "\(lon)"])
        if isIOS17Error(r1) {
            // Fall back to pymobiledevice3
            await startPymd(lat: lat, lon: lon, udid: udid)
            return
        }
        if isError(r1) {
            errorMsg = r1.isEmpty ? "Unknown error. Check iPhone is unlocked and trusted." : r1
            status   = "Error"; return
        }

        activate(lat: lat, lon: lon)
        startKeepAlive(lat: lat, lon: lon, udid: udid, legacy: true)
    }

    func stop(udid: String? = nil) {
        keepAlive?.cancel(); keepAlive = nil
        guard isActive else { return }
        let uid = udid
        let pymd = usePymd
        let h = activeRSDHost
        let p = activeRSDPort
        Task.detached(priority: .userInitiated) {
            if pymd {
                shell("pymobiledevice3 developer dvt simulate-location clear --rsd \(h) \(p) 2>&1")
            } else {
                var cmd = "idevicesetlocation"
                if let u = uid { cmd += " -u \(u)" }
                cmd += " reset"  // legacy idevicesetlocation
                shell(cmd)
            }
        }
        isActive = false; coordinate = nil; status = "Ready"; errorMsg = nil; usePymd = false
    }

    // MARK: iOS 17+ via pymobiledevice3

    private func startPymd(lat: Double, lon: Double, udid: String?) async {
        let host = rsdHost.trimmingCharacters(in: .whitespaces)
        let portNum = Int(rsdPort.trimmingCharacters(in: .whitespaces)) ?? 0

        guard !host.isEmpty, portNum > 0 else {
            needsTunnel = true
            tunnelRunning = false
            status   = "Tunnel required for iOS 17+"
            errorMsg = nil
            return
        }

        status = "Connecting via tunnel…"
        let r = await Task.detached(priority: .userInitiated) {
            shell("pymobiledevice3 developer dvt simulate-location set --rsd \(host) \(portNum) -- \(lat) \(lon) 2>&1")
        }.value

        if isError(r) {
            errorMsg = friendlyPymdError(r)
            status = "Error"; return
        }

        usePymd = true
        needsTunnel    = false
        tunnelRunning  = true
        activeRSDHost  = host
        activeRSDPort  = portNum
        activate(lat: lat, lon: lon)
        startKeepAlive(lat: lat, lon: lon, udid: udid, legacy: false)
    }

    func retryAfterTunnel(lat: Double, lon: Double, udid: String?) async {
        await startPymd(lat: lat, lon: lon, udid: udid)
    }

    // MARK: Tunnel helpers

    func openTunnelInTerminal() {
        let pyPath = findPymobiledevice3()
        let script = """
        tell application "Terminal"
            activate
            do script "echo 'Starting iOS 17+ location tunnel — leave this window open while using GhostLocation' && sudo \(pyPath) remote tunneld"
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    private func findPymobiledevice3() -> String {
        let candidates = [
            "/Users/\(NSUserName())/Library/Python/3.9/bin/pymobiledevice3",
            "/Users/\(NSUserName())/Library/Python/3.11/bin/pymobiledevice3",
            "/Users/\(NSUserName())/Library/Python/3.12/bin/pymobiledevice3",
            "/opt/homebrew/bin/pymobiledevice3",
            "/usr/local/bin/pymobiledevice3",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "pymobiledevice3"
    }

    // MARK: Helpers

    private func activate(lat: Double, lon: Double) {
        isActive   = true
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        status     = "Spoofing active"
        errorMsg   = nil
    }

    private func startKeepAlive(lat: Double, lon: Double, udid: String?, legacy: Bool) {
        keepAlive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                if legacy {
                    let _ = await Task.detached(priority: .background) {
                        var cmd = "idevicesetlocation"
                        if let u = udid { cmd += " -u \(u)" }
                        cmd += " -- \(lat) \(lon)"
                        shell(cmd)
                    }.value
                } else {
                    let h = self.activeRSDHost, p = self.activeRSDPort
                    let _ = await Task.detached(priority: .background) {
                        shell("pymobiledevice3 developer dvt simulate-location set --rsd \(h) \(p) -- \(lat) \(lon) 2>&1")
                    }.value
                }
            }
        }
    }

    private func run(_ tool: String, udid: String?, args: [String]) async -> String {
        await Task.detached(priority: .userInitiated) {
            var cmd = tool
            if let u = udid { cmd += " -u \(u)" }
            cmd += " " + args.joined(separator: " ")
            return shell(cmd)
        }.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func friendlyPymdError(_ s: String) -> String {
        let low = s.lowercased()
        if low.contains("timeouterror") || low.contains("timed out") || low.contains("timeout") {
            return "Connection timed out — make sure the tunnel terminal is still open (sudo pymobiledevice3 remote tunneld) and re-enter the RSD values."
        }
        if low.contains("connectionrefused") || low.contains("connection refused") || low.contains("connection reset") {
            return "Tunnel connection refused — restart the tunnel terminal and re-enter the RSD values."
        }
        if low.contains("no route to host") || low.contains("network unreachable") {
            return "Can't reach device — check USB/WiFi and that the tunnel is running."
        }
        if low.contains("invalid host") || low.contains("invalid port") || low.contains("connect: invalid argument") {
            return "Invalid RSD host or port — copy the exact values from the tunnel terminal."
        }
        if s.isEmpty {
            return "Failed — check RSD values and that the tunnel terminal is still open."
        }
        // Return only the last meaningful line, not the full traceback
        let lines = s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("|") && !$0.hasPrefix("Traceback") && !$0.hasPrefix("File ") }
        return lines.last ?? s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isIOS17Error(_ s: String) -> Bool {
        let low = s.lowercased()
        return low.contains("ios 17") || low.contains("not supported on ios") || low.contains("invalid service")
    }

    private func isError(_ s: String) -> Bool {
        let low = s.lowercased()
        return low.contains("error") || low.contains("failed") || low.contains("no device") || low.contains("could not")
    }
}
