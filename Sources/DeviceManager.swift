import Foundation

struct IOSDevice: Identifiable, Equatable {
    let id: String
    let name: String
    var shortUDID: String { String(id.prefix(8)) + "…" }
}

enum PairStatus {
    case unknown, paired, unpaired, validating
}

@MainActor
class DeviceManager: ObservableObject {
    @Published var devices: [IOSDevice] = []
    @Published var selectedDevice: IOSDevice?
    @Published var toolsInstalled = false
    @Published var checking = false
    @Published var diagnosticMsg = ""   // shown in sidebar
    @Published var pairStatus: PairStatus = .unknown
    @Published var pairing = false

    private var refreshTask: Task<Void, Never>?

    init() {
        Task { await checkTools() }
    }

    func checkTools() async {
        checking = true
        // Use FileManager — avoids the macOS `which` bug where it outputs
        // "X not found" to stdout making a string-empty check unreliable.
        let knownPaths = [
            "/opt/homebrew/bin/idevicesetlocation",  // Apple Silicon
            "/usr/local/bin/idevicesetlocation",     // Intel
        ]
        toolsInstalled = knownPaths.contains { FileManager.default.fileExists(atPath: $0) }
        checking = false
        if toolsInstalled {
            await validatePairing()
            await refresh()
        }
        startAutoRefresh()
    }

    // MARK: Pairing

    func validatePairing() async {
        pairStatus = .validating
        let out = await Task.detached(priority: .userInitiated) {
            shell("idevicepair validate 2>&1")
        }.value

        if out.lowercased().contains("success") || out.lowercased().contains("paired") {
            pairStatus = .paired
            diagnosticMsg = ""
        } else if out.lowercased().contains("no device") || out.lowercased().contains("could not connect") {
            pairStatus = .unpaired
            diagnosticMsg = "No device found. Connect USB & tap Trust on iPhone."
        } else if out.lowercased().contains("invalid host") || out.lowercased().contains("not paired") {
            pairStatus = .unpaired
            diagnosticMsg = "Pairing needed — tap Pair Device below."
        } else {
            pairStatus = .unknown
            diagnosticMsg = out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Connect iPhone via USB and tap Trust."
                : out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func pairDevice() async {
        pairing = true
        diagnosticMsg = "Pairing… check your iPhone screen."

        let out = await Task.detached(priority: .userInitiated) {
            shell("idevicepair pair 2>&1")
        }.value

        let lower = out.lowercased()
        if lower.contains("success") {
            pairStatus = .paired
            diagnosticMsg = "Paired! Refreshing devices…"
            await refresh()
        } else if lower.contains("user denied") || lower.contains("denied") {
            diagnosticMsg = "Tap Trust (not Cancel) on your iPhone, then retry."
        } else if lower.contains("password") || lower.contains("passcode") {
            diagnosticMsg = "Unlock your iPhone first, then tap Trust, then retry."
        } else {
            diagnosticMsg = out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Pairing failed. Unlock iPhone, tap Trust, retry."
                : out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        pairing = false
    }

    // MARK: Device scan

    func refresh() async {
        guard toolsInstalled else { return }

        let raw = await Task.detached(priority: .userInitiated) {
            shell("idevice_id -l 2>&1")
        }.value

        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // UDIDs are 40-hex or UUID format
        let udids = lines.filter { isUDID($0) }

        if udids.isEmpty {
            // Show diagnostic from raw output if useful
            let lower = raw.lowercased()
            if lower.contains("no device") || raw.trimmingCharacters(in: .whitespaces).isEmpty {
                if pairStatus != .paired {
                    diagnosticMsg = "No device detected. Connect USB & tap Trust on iPhone."
                } else {
                    diagnosticMsg = "Device not found. Try: unplug → replug USB."
                }
            } else if !raw.trimmingCharacters(in: .whitespaces).isEmpty {
                diagnosticMsg = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            diagnosticMsg = ""
        }

        var found: [IOSDevice] = []
        for udid in udids {
            let name = await Task.detached(priority: .userInitiated) {
                let raw = shell("ideviceinfo -u \(udid) -k DeviceName 2>/dev/null")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? "iPhone" : raw
            }.value
            found.append(IOSDevice(id: udid, name: name))
        }

        devices = found
        if found.isEmpty { pairStatus = .unpaired }
        if selectedDevice == nil || !found.contains(where: { $0.id == selectedDevice?.id }) {
            selectedDevice = found.first
        }
    }

    private func isUDID(_ s: String) -> Bool {
        let clean = s.replacingOccurrences(of: "-", with: "").uppercased()
        let allHex = clean.allSatisfy({ $0.isHexDigit })
        let hex    = s.count == 40 && allHex                          // old format
        let uuid   = s.count == 36 && s.filter({ $0 == "-" }).count == 4 && allHex  // standard UUID
        let ios17  = s.count >= 24 && s.count <= 26 && s.contains("-") && allHex    // iOS 17 8hex-16hex
        return hex || uuid || ios17
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    func openTerminalWithDiagnostics() {
        let script = """
        tell application "Terminal"
            activate
            do script "echo '--- GhostLocation Diagnostics ---' && idevice_id -l && echo '---' && idevicepair validate && echo '--- If unpaired, run: idevicepair pair ---'"
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    func installHomebrew() {
        let script = """
        tell application "Terminal"
            activate
            do script "/bin/bash -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)' && brew install libimobiledevice && echo '✓ Done! Relaunch GhostLocation.'"
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    deinit { refreshTask?.cancel() }
}
