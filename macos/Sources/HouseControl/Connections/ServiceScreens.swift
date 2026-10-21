import SwiftUI

// The screen of each platform, under its tile and name (ConnectionsView's `ServiceScreen`).

// MARK: - Home Assistant

struct HomeAssistantScreen: View {
    @Bindable var model: ConnectionsModel

    var body: some View {
        let info = model.info(.homeAssistant)
        if model.connected(.homeAssistant) {
            ConnectedHeader(model: model, service: .homeAssistant, title: "Server", name: info["name"] as? String ?? "Home Assistant",
                            line: [info["url"] as? String, (info["version"] as? String).flatMap { $0.isEmpty ? nil : "version \($0)" }]
                                .compactMap { $0 }.joined(separator: " · "))
            ServiceDevices(model: model, service: .homeAssistant)
        } else {
            ConnectionSection("On your network") {
                if model.scanning.contains(.homeAssistant) {
                    Busy(text: "Looking for Home Assistant…")
                } else {
                    let found = model.found[.homeAssistant] ?? []
                    if found.isEmpty {
                        Footnote("None found by itself. Type its address below.")
                    }
                    ForEach(Array(found.enumerated()), id: \.offset) { index, server in
                        if index > 0 { Divider().overlay(Theme.line) }
                        let url = server["url"] as? String ?? ""
                        DeviceRow(name: server["name"] as? String ?? "Home Assistant",
                                  line: [url, (server["version"] as? String).flatMap { $0.isEmpty ? nil : "version \($0)" }]
                                      .compactMap { $0 }.joined(separator: " · ")) {
                            Button(model.haURL == url ? "Selected" : "Use") { model.haURL = url }
                                .disabled(model.haURL == url)
                        }
                    }
                    LookAgain { model.scan(.homeAssistant) }
                }
            }
            ConnectionSection("Connect") {
                Field(label: "Address") {
                    TextField("http://homeassistant.local:8123", text: $model.haURL)
                        .autocorrectionDisabled()
                }
                Field(label: "Access token") {
                    SecureField("Long-lived access token", text: $model.haToken)
                        .onSubmit { model.connectHomeAssistant() }
                }
                Steps(steps: ["In Home Assistant, open your profile (your name at the bottom left) → Security.",
                              "Under “Long-lived access tokens” press Create token, name it “House Control”, copy it here."])
                Button { model.connectHomeAssistant() } label: {
                    Text(model.haBusy ? "Connecting…" : "Connect").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.canConnectHomeAssistant)
                if let error = model.haError { Footnote(error, bad: true) }
            }
            Footnote("The token stays on this Mac (and goes to the iPhones you paired, over their encrypted link). Lights, switches, climate devices and temperature sensors appear here.")
        }
    }
}

// MARK: - Philips Hue

struct HueScreen: View {
    @Bindable var model: ConnectionsModel

    var body: some View {
        let info = model.info(.hue)
        if model.connected(.hue) {
            ConnectedHeader(model: model, service: .hue, title: "Bridge", name: info["name"] as? String ?? "Hue Bridge",
                            line: [info["host"] as? String, info["bridgeId"] as? String].compactMap { $0 }.filter { !$0.isEmpty }
                                .joined(separator: " · "))
            ServiceDevices(model: model, service: .hue)
        } else if let pairing = model.huePairing {
            ConnectionSection("Pairing") {
                HStack(spacing: 16) {
                    PressButton(waiting: pairing.error == nil)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Press the round button on the bridge").font(.system(size: 14, weight: .semibold))
                        Text(pairing.error ?? "\(pairing.name) · waiting \(pairing.secondsLeft) s")
                            .font(.system(size: 12)).foregroundStyle(pairing.error == nil ? Theme.faint : Theme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    if pairing.error != nil { Button("Try again") { model.retryPairing() }.buttonStyle(.borderedProminent) }
                    Button("Cancel") { model.stopPairing() }.buttonStyle(.bordered)
                }
                Footnote("The big button on top of the Hue Bridge lets one app in for 30 seconds. House Control keeps the key it gets, on this Mac.")
            }
        } else {
            ConnectionSection("On your network") {
                if model.scanning.contains(.hue) {
                    Busy(text: "Looking for Hue Bridges…")
                } else {
                    let found = model.found[.hue] ?? []
                    if found.isEmpty {
                        Footnote("No bridge found by itself. Type its address below (the Hue app shows it under Settings → My Hue system).")
                    }
                    ForEach(Array(found.enumerated()), id: \.offset) { index, bridge in
                        if index > 0 { Divider().overlay(Theme.line) }
                        let name = bridge["name"] as? String ?? "Hue Bridge"
                        DeviceRow(name: name, line: [bridge["host"] as? String, bridge["bridgeId"] as? String]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")) {
                            Button("Pair") {
                                model.pairHue(host: bridge["host"] as? String ?? "", bridgeId: bridge["bridgeId"] as? String, name: name)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    LookAgain { model.scan(.hue) }
                }
            }
            ConnectionSection("Or by address") {
                Field(label: "Bridge address") {
                    TextField("e.g. 192.168.1.20", text: $model.hueHost)
                        .autocorrectionDisabled()
                        .onSubmit { model.pairHue(host: model.hueHost) }
                }
                Button { model.pairHue(host: model.hueHost) } label: { Text("Pair").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(model.hueHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// The Hue Bridge's round button, pulsing while the app waits for it (`.press-button`).
private struct PressButton: View {
    let waiting: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: "#f4f5f8"), Color(hex: "#c9ccd6")], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 52, height: 52)
            .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
            .overlay {
                if waiting {
                    Circle()
                        .fill(RadialGradient(colors: [.white, Color(hex: "#dfe3ea"), Color(hex: "#c3c8d2")],
                                             center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 16))
                        .frame(width: 26, height: 26)
                        .phaseAnimator([false, true]) { circle, pressed in
                            circle
                                .scaleEffect(pressed ? 0.9 : 1)
                                .overlay(Circle().strokeBorder(Color(red: 60 / 255, green: 140 / 255, blue: 1).opacity(pressed ? 0.6 : 0), lineWidth: 3))
                        } animation: { _ in .easeInOut(duration: 0.8) }
                } else {
                    Circle().fill(Color(hex: "#dfe3ea")).frame(width: 26, height: 26)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Apple Home

struct HomeKitScreen: View {
    let model: ConnectionsModel

    var body: some View {
        let info = model.info(.homeKit)
        let connected = model.connected(.homeKit)
        if connected {
            ConnectionSection("From your iPhone") {
                DeviceRow(name: (info["from"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "iPhone",
                          line: "\(info["count"] as? Int ?? 0) devices · sent \(sent(info["updated"] as? Double ?? 0))")
                Button("Forget this list") { model.disconnect(.homeKit) }.buttonStyle(.bordered)
            }
            ServiceDevices(model: model, service: .homeKit)
        }
        ConnectionSection(connected ? "How it works" : "Set it up on your iPhone") {
            Steps(steps: ["Pair your iPhone with this Mac: Pair iPhone, in the sidebar.",
                          "On the iPhone: House Control → Settings → Apple Home → Connect, and allow access to your Home data.",
                          "Its lamps, air conditioners and thermometers appear here. Link them like any other device."])
            Footnote("Apple lets only iPhone, iPad and App Store apps use HomeKit, so the iPhone app switches these devices. On the Mac they show what you set, but stay simulated.")
        }
    }

    private func sent(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Smart Life

struct SmartLifeScreen: View {
    @Bindable var model: ConnectionsModel

    var body: some View {
        if model.smartLifeSignedIn {
            ConnectionSection("Smart Life account") {
                DeviceRow(name: (model.account["account"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Signed in",
                          line: "User Code \(model.account["userCode"] as? String ?? "")")
                HStack(spacing: 8) {
                    Button("Refresh devices") { model.loadTuyaDevices() }
                    Button("Sign out") { model.signOut() }
                }
                .buttonStyle(.bordered)
                Footnote("Pick a lamp or an AC in Edit Home, choose its device under “Real device”, then press “Save & apply”.")
            }
            TuyaDevices(model: model)
        } else {
            ConnectionSection("Sign in with the Smart Life app") {
                Steps(steps: ["In the Smart Life app open Me → ⚙ Settings → Account and Security and copy the User Code at the bottom.",
                              "Type it here and press “Show QR code”.",
                              "Scan the code with the Smart Life app and confirm."])
                Field(label: "User Code") {
                    TextField("e.g. aB12cD3", text: $model.userCode)
                        .autocorrectionDisabled()
                        .onSubmit { model.showLoginCode() }
                }
                Button { model.showLoginCode() } label: { Text("Show QR code").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                if let qr = model.loginQR {
                    QRCard(content: qr).frame(maxWidth: .infinity)
                }
                if !model.loginMessage.isEmpty { Footnote(model.loginMessage, bad: model.loginFailed) }
                Footnote("Free and needs no Tuya developer account: this is the same sign-in the Home Assistant integration uses. The session is stored only on this Mac.")
            }
        }

        // The developer-project route stays available for those who already have one.
        // A disclosure whose whole title opens it (a DisclosureGroup's opens only by its chevron).
        Button { withAnimation(.easeOut(duration: 0.2)) { model.tuyaOpen.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(model.tuyaOpen ? 90 : 0))
                Text("Advanced: Tuya Cloud project instead").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if model.tuyaOpen {
            Card(padding: 16) { VStack(alignment: .leading, spacing: 14) {
                Footnote("Only if you already have a project on platform.tuya.com with your app account linked. The QR sign-in above takes priority when both are set.")
                Field(label: "Access ID") {
                    TextField("Access ID / Client ID", text: $model.tuyaAccessId).autocorrectionDisabled()
                }
                Field(label: "Access Secret") {
                    SecureField(model.tuya["hasSecret"] as? Bool == true ? "•••••••• (saved — leave empty to keep)" : "Access Secret / Client Secret",
                                text: $model.tuyaSecret)
                }
                Field(label: "Data center") {
                    Picker("Data center", selection: $model.tuyaRegion) {
                        ForEach(ConnectionsModel.regions, id: \.0) { id, label in Text("\(label) (\(id))").tag(id) }
                    }
                    .labelsHidden()
                }
                Button { model.saveTuya() } label: { Text("Save & fetch devices").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
            } }
            .padding(.top, -10)
        }
        if !model.smartLifeSignedIn, model.tuyaOpen { TuyaDevices(model: model) }
    }
}

/// The account's devices as Tuya reports them.
private struct TuyaDevices: View {
    let model: ConnectionsModel

    var body: some View {
        if model.tuyaBusy {
            Busy(text: "Talking to Smart Life…")
        } else if let error = model.tuyaError {
            Footnote(error, bad: true)
        } else if let devices = model.tuyaDevices {
            if devices.isEmpty {
                Footnote("Connected, but this account has no devices yet.", bad: true)
            } else {
                DeviceGroup(title: "\(devices.count) devices in your account", devices: devices, used: model.used)
            }
        }
    }
}

// MARK: - Shared

/// A connected platform: who it is, and refreshing or disconnecting it.
private struct ConnectedHeader: View {
    let model: ConnectionsModel
    let service: ConnectionsModel.Service
    let title: String
    let name: String
    let line: String

    var body: some View {
        ConnectionSection(title) {
            DeviceRow(name: name, line: line)
            HStack(spacing: 8) {
                Button("Refresh devices") { model.load() }
                Button("Disconnect") { model.disconnect(service) }
            }
            .buttonStyle(.bordered)
        }
    }
}
