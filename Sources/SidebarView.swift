import SwiftUI
import CoreLocation

struct SidebarView: View {
    @ObservedObject var devices: DeviceManager
    @ObservedObject var spoofer: LocationSpoofer
    @ObservedObject var router: RouteSimulator
    @Binding var mode: TravelMode
    @Binding var pinCoord: CLLocationCoordinate2D?
    @Binding var originCoord: CLLocationCoordinate2D?
    @Binding var destCoord: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if devices.checking {
                Spacer(); ProgressView("Checking tools…"); Spacer()
            } else if !devices.toolsInstalled {
                installPrompt
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        devicesSection
                        modeSection
                        if mode == .pin {
                            pinSection
                        } else {
                            routeSection
                        }
                        wifiSection
                    }
                    .padding(14)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.cyan.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: "location.slash.fill")
                    .foregroundColor(.cyan).font(.system(size: 15, weight: .semibold))
            }
            Text("GhostLocation").font(.system(size: 16, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: Install Prompt

    var installPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 36)).foregroundColor(.orange)
            Text("Setup Required").font(.headline)
            Text("Homebrew + libimobiledevice must be installed first.")
                .font(.callout).multilineTextAlignment(.center).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                stepRow("1", "Open Terminal (⌘ Space → Terminal)")
                stepRow("2", "Paste and run each command:")
            }

            VStack(alignment: .leading, spacing: 6) {
                monoBlock("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                monoBlock("echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile && eval \"$(/opt/homebrew/bin/brew shellenv)\"")
                monoBlock("brew install libimobiledevice")
            }

            Button("Open Terminal Now") { devices.installHomebrew() }
                .buttonStyle(.borderedProminent).tint(.cyan)

            Button("Re-check After Installing") { Task { await devices.checkTools() } }
                .buttonStyle(.plain).foregroundColor(.cyan).font(.callout)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func stepRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num).font(.caption.bold())
                .frame(width: 16, height: 16)
                .background(Color.cyan.opacity(0.2))
                .clipShape(Circle())
                .foregroundColor(.cyan)
            Text(text).font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func monoBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.primary)
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(5)
            .textSelection(.enabled)
    }

    // MARK: Devices

    var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Devices", icon: "iphone")

            if devices.devices.isEmpty {
                // Diagnostic message + Pair button
                VStack(alignment: .leading, spacing: 8) {
                    if !devices.diagnosticMsg.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange).font(.caption)
                            Text(devices.diagnosticMsg)
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(6)
                    } else {
                        infoBox {
                            Label("Connect iPhone via USB. Tap Trust if prompted.", systemImage: "cable.connector")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    // iOS 17+ hint
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle").foregroundColor(.cyan).font(.caption)
                        Text("iOS 17+: Settings → Privacy & Security → **Developer Mode** → ON (requires restart)")
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Pair button
                    if devices.pairing {
                        HStack { ProgressView().scaleEffect(0.7); Text("Pairing…").font(.caption).foregroundColor(.secondary) }
                    } else {
                        Button { Task { await devices.pairDevice() } } label: {
                            Label("Pair Device", systemImage: "cable.connector.horizontal")
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    }
                }
            } else {
                ForEach(devices.devices) { d in deviceRow(d) }
                if !devices.diagnosticMsg.isEmpty {
                    Text(devices.diagnosticMsg).font(.caption2).foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button { Task { await devices.refresh() } }
                label: { Label("Refresh", systemImage: "arrow.clockwise").font(.caption) }
                    .buttonStyle(.plain).foregroundColor(.cyan)

                Button { devices.openTerminalWithDiagnostics() }
                label: { Label("Diagnose", systemImage: "terminal").font(.caption) }
                    .buttonStyle(.plain).foregroundColor(.secondary)
            }
        }
    }

    func deviceRow(_ device: IOSDevice) -> some View {
        let sel = devices.selectedDevice?.id == device.id
        return HStack(spacing: 8) {
            Image(systemName: "iphone").foregroundColor(sel ? .cyan : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.callout).fontWeight(sel ? .semibold : .regular)
                Text(device.shortUDID).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            }
            Spacer()
            if sel { Image(systemName: "checkmark.circle.fill").foregroundColor(.cyan).font(.caption) }
        }
        .padding(8)
        .background(sel ? Color.cyan.opacity(0.12) : Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(sel ? Color.cyan.opacity(0.4) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { devices.selectedDevice = device }
    }

    // MARK: Mode Picker

    var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Mode", icon: "location.circle")
            HStack(spacing: 6) {
                ForEach(TravelMode.allCases) { m in
                    Button { switchMode(m) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: m.icon).font(.system(size: 18))
                            Text(m.rawValue).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(mode == m ? Color.cyan.opacity(0.2) : Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(mode == m ? Color.cyan : Color.clear, lineWidth: 1.5))
                        .foregroundColor(mode == m ? .cyan : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func switchMode(_ m: TravelMode) {
        guard m != mode else { return }
        spoofer.stop()
        router.stop()
        mode = m
        pinCoord    = nil
        originCoord = nil
        destCoord   = nil
    }

    // MARK: Pin Mode

    var pinSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Target Location", icon: "mappin.circle")
            if let c = pinCoord {
                infoBox {
                    VStack(alignment: .leading, spacing: 3) {
                        coordRow("Lat", c.latitude)
                        coordRow("Lon", c.longitude)
                    }
                }
            } else {
                infoBox { Text("Click the map to drop your fake pin")
                    .font(.caption).foregroundColor(.secondary) }
            }

            statusRow(active: spoofer.isActive, text: spoofer.status)

            if let err = spoofer.errorMsg {
                Text(err).font(.caption2).foregroundColor(.red)
                    .padding(6).background(Color.red.opacity(0.08)).cornerRadius(4)
            }

            // iOS 17+ tunnel panel
            if spoofer.needsTunnel {
                tunnelPanel
            } else {
                Button { togglePin() } label: {
                    mainButtonLabel(
                        icon: spoofer.isActive ? "location.slash.fill" : "location.fill",
                        text: spoofer.isActive ? "Stop Spoofing" : "Start Spoofing"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(spoofer.isActive ? .red : .cyan)
                .disabled(pinCoord == nil || devices.selectedDevice == nil)
            }
        }
    }

    var tunnelPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "network").foregroundColor(.orange).font(.caption)
                Text("Enter RSD values").font(.caption.bold()).foregroundColor(.orange)
            }

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Host").font(.caption2).foregroundColor(.secondary)
                    TextField("fd44:6c4d:e6ce::1", text: $spoofer.rsdHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Port").font(.caption2).foregroundColor(.secondary)
                    TextField("58412", text: $spoofer.rsdPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 60)
                }
            }

            Button {
                guard let c = pinCoord else { return }
                let uid = devices.selectedDevice?.id
                Task { await spoofer.retryAfterTunnel(lat: c.latitude, lon: c.longitude, udid: uid) }
            } label: {
                Label("Start Spoofing", systemImage: "location.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent).tint(.cyan)
            .disabled(pinCoord == nil || spoofer.rsdHost.isEmpty || spoofer.rsdPort.isEmpty)
        }
        .padding(10)
        .background(Color.orange.opacity(0.07))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    func togglePin() {
        guard let c = pinCoord else { return }
        let uid = devices.selectedDevice?.id
        if spoofer.isActive { spoofer.stop(udid: uid) }
        else { Task { await spoofer.start(lat: c.latitude, lon: c.longitude, udid: uid) } }
    }

    // MARK: Route Mode

    var routeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Route", icon: "car.fill")

            // Waypoint status
            infoBox {
                VStack(alignment: .leading, spacing: 5) {
                    waypointRow("A  Start", coord: originCoord, color: .green,
                                hint: "Click map to set start")
                    Divider()
                    waypointRow("B  End", coord: destCoord, color: .red,
                                hint: originCoord == nil ? "Set start first" : "Click map to set end")
                }
            }

            // Route status / loading
            if router.isLoading {
                HStack { ProgressView().scaleEffect(0.7); Text("Calculating…").font(.caption).foregroundColor(.secondary) }
            } else if !router.status.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "map").font(.caption).foregroundColor(.cyan)
                    Text(router.status).font(.caption).foregroundColor(.secondary)
                }
            }

            // Progress bar
            if router.isRunning || router.progress > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(NSColor.separatorColor)).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3).fill(Color.cyan)
                                .frame(width: geo.size.width * router.progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    HStack {
                        Text(String(format: "%.0f%%", router.progress * 100)).font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        if let c = router.currentCoord {
                            Text(String(format: "%.4f, %.4f", c.latitude, c.longitude))
                                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Speed slider
            if router.routePolyline != nil {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Speed").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(router.speedMPH)) mph")
                            .font(.caption.bold()).foregroundColor(.cyan)
                            .monospacedDigit()
                    }
                    Slider(value: $router.speedMPH, in: 60...170, step: 1)
                        .tint(.cyan)
                    HStack {
                        Text("60").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text("170").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            statusRow(active: router.isRunning, text: router.isRunning ? "Moving…" : (router.progress == 1 ? "Arrived!" : "Ready"))

            // Action button
            Button { toggleRoute() } label: {
                mainButtonLabel(
                    icon: router.isRunning ? "stop.circle.fill" : "play.circle.fill",
                    text: router.isRunning ? "Stop" : (router.routePolyline == nil ? "Waiting for route…" : "Start \(mode.rawValue)")
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(router.isRunning ? .red : .cyan)
            .disabled(!canStartRoute)

            if originCoord != nil || destCoord != nil {
                Button { clearRoute() } label: {
                    Label("Clear Route", systemImage: "xmark.circle").font(.caption)
                }
                .buttonStyle(.plain).foregroundColor(.secondary)
            }
        }
    }

    var canStartRoute: Bool {
        !router.isRunning && router.routePolyline != nil && devices.selectedDevice != nil
    }

    func toggleRoute() {
        let uid = devices.selectedDevice?.id
        if router.isRunning { router.stop() }
        else { router.start(udid: uid, rsdHost: spoofer.rsdHost, rsdPort: spoofer.rsdPort) }
    }

    func clearRoute() {
        router.stop()
        originCoord = nil
        destCoord   = nil
        router.routePolyline = nil
        router.currentCoord  = nil
        router.progress      = 0
        router.status        = ""
    }

    func waypointRow(_ label: String, coord: CLLocationCoordinate2D?, color: Color, hint: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(coord != nil ? color : Color.gray.opacity(0.4)).frame(width: 8, height: 8)
            Text(label).font(.caption.bold()).foregroundColor(coord != nil ? .primary : .secondary)
            Spacer()
            if let c = coord {
                Text(String(format: "%.4f, %.4f", c.latitude, c.longitude))
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            } else {
                Text(hint).font(.caption2).foregroundColor(.secondary).italic()
            }
        }
    }

    // MARK: WiFi tip

    var wifiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Go Wireless", systemImage: "wifi").font(.caption.bold()).foregroundColor(.cyan)
            Text("After first USB connection, enable **WiFi Sync** in Finder for your iPhone. Then unplug — works over WiFi on the same network.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.cyan.opacity(0.07)).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
    }

    // MARK: Helpers

    func label(_ t: String, icon: String) -> some View {
        Label(t, systemImage: icon).font(.caption.bold()).foregroundColor(.secondary).textCase(.uppercase)
    }

    func infoBox<C: View>(@ViewBuilder content: () -> C) -> some View {
        content().padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor)).cornerRadius(6)
    }

    func coordRow(_ lbl: String, _ val: Double) -> some View {
        HStack(spacing: 4) {
            Text("\(lbl):").font(.caption).foregroundColor(.secondary).frame(width: 24, alignment: .leading)
            Text(String(format: "%.6f°", val)).font(.system(.caption, design: .monospaced))
        }
    }

    func statusRow(active: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(active ? Color.green : Color(NSColor.tertiaryLabelColor)).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundColor(active ? .green : .secondary)
        }
    }

    func mainButtonLabel(icon: String, text: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 9)
    }
}
