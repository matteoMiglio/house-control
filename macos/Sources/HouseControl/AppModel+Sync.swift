import AppKit
import HouseCore
import HouseSmartLife

extension AppModel {
    // MARK: - iPhone sync

    /// The name paired iPhones see (HOUSE_COMPUTER_NAME replaces it for screenshots).
    private var computerName: String {
        ProcessInfo.processInfo.environment["HOUSE_COMPUTER_NAME"] ?? Host.current().localizedName ?? "Mac"
    }

    func startSync() {
        sync.snapshot = { [unowned self] in
            SyncState(macName: self.computerName,
                      revision: self.plans.customPlanRevision ?? "",
                      plan: try? Data(contentsOf: self.plans.customPlanURL),
                      userCode: self.smartLife.userCode,
                      smartLifeConnected: self.smartLife.isSmartLifeConnected,
                      connections: self.hub.shareableConnections)
        }
        sync.onCatalog = { [weak self] devices, phone in
            guard let self, let catalog = self.hub.homeKit as? RemoteCatalogService else { return }
            catalog.update(devices: devices, from: phone)
            self.hosts[.editor]?.call("servicesChanged", self.hub.servicesInfo)
        }
        // A home set up or edited on the iPhone becomes this Mac's home too.
        sync.onPlan = { [weak self] data, phone in self?.receivedPlan(data, from: phone) }
        sync.onConnections = { [weak self] shared, userCode, _ in
            guard let self else { return }
            if !userCode.isEmpty { self.phoneUserCode = userCode }
            if self.hub.adoptConnections(shared) {
                self.connectionsChanged()
                self.hosts[.editor]?.call("servicesChanged", self.hub.servicesInfo)
            }
        }
        sync.onPeersChanged = { [weak self] in self?.refreshPairingWindow() }
        sync.onShowQR = { [weak self] content, device in self?.showLoginCode(content, for: device) }
        sync.start() // only listens once a phone has been paired
    }

    /// Stores a plan an iPhone saved. The first one becomes the active home; later ones
    /// replace it (a Mac that switched to a demo plan stays there, like the phone does).
    private func receivedPlan(_ data: Data, from phone: String) {
        let first = !plans.hasCustomPlan
        do {
            try plans.saveCustom(data: data, select: first || plans.activePlan == "custom")
        } catch {
            NSLog("House Control: could not store the plan from %@: %@", phone, error.localizedDescription)
            return
        }
        reloadLinks()
        widgets.isReady = false
        hosts[.primary]?.load()
        if island?.isShown == true { hosts[.island]?.load() }
        sync.broadcast()
        // An open editor takes the new plan unless it holds unsaved changes of its own.
        if let host = hosts[.editor], let plan = plans.customPlan() { host.call("planArrived", plan, phone) }
    }

    /// Shows the QR code an iPhone scans once to find this Mac and receive its floor plan.
    func pairPhone() {
        panel.hide()
        let pairing = sync.enable(name: computerName)
        if pairingWindow == nil {
            let window = QRWindowController(title: "Pair iPhone")
            window.onClose = { [weak self] in self?.pairingWindow = nil }
            window.addButton("Copy Pairing Link") { [weak self] in
                guard let link = self?.sync.pairing?.link else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
            }
            window.addButton("Reset Pairing…") { [weak self] in self?.resetPairing() }
            pairingWindow = window
        }
        pairingWindow?.show(code: pairing.link,
                            headline: "Scan with House Control on your iPhone",
                            detail: "On the iPhone open Settings → Pair with Mac. Both devices must be on the same Wi-Fi. "
                                + "Your floor plan, device links and connections stay the same on both, whichever one you edit; "
                            + "they travel straight between them, encrypted with the key in this code.")
        refreshPairingWindow()
    }

    private func resetPairing() {
        let alert = NSAlert()
        alert.messageText = "Reset pairing?"
        alert.informativeText = "Every iPhone paired so far stops syncing until it scans the new code."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        sync.reset(name: computerName)
        pairPhone()
    }

    private func refreshPairingWindow() {
        connectedDevices = sync.connectedDevices
        let devices = connectedDevices
        if !devices.isEmpty {
            pairingWindow?.setStatus("Connected: \(devices.joined(separator: ", "))", active: true)
        } else if sync.isAdvertised {
            pairingWindow?.setStatus("Waiting for an iPhone…", active: false)
        } else {
            // Until macOS lets the app use the local network, no phone can find this Mac.
            pairingWindow?.setStatus("Allow Local Network access for House Control in System Settings → Privacy & Security",
                                     active: false)
        }
    }

    /// A paired iPhone signs in to Smart Life on its own, but its login code has to be
    /// scanned by the Smart Life app on that same phone, so it borrows this Mac's screen.
    ///
    /// The window does not follow the phone's connection: to scan the code the user switches
    /// to Smart Life, our app goes to the background and iOS disconnects it. It closes when
    /// the phone says it is signed in (or gave up), when the user closes it, or after ten
    /// minutes, by which time the login ticket is long dead.
    private func showLoginCode(_ content: String?, for device: String) {
        loginWindowExpiry?.cancel()
        loginWindowExpiry = nil
        guard let content, content.hasPrefix("tuyaSmart--qrLogin?token=") else {
            loginWindow?.close()
            loginWindow = nil
            return
        }
        let expiry = DispatchWorkItem { [weak self] in
            self?.loginWindow?.close()
            self?.loginWindow = nil
        }
        loginWindowExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: expiry)
        if loginWindow == nil {
            let window = QRWindowController(title: "Smart Life Sign-In for \(device)")
            window.onClose = { [weak self] in self?.loginWindow = nil }
            loginWindow = window
        }
        loginWindow?.show(code: content,
                          headline: "Scan with the Smart Life app on \(device)",
                          detail: "Switch to Smart Life on the iPhone, tap the scanner on its Home tab and confirm the login. "
                              + "Then return to House Control: this window closes once the iPhone is signed in.")
        loginWindow?.setStatus("Requested by \(device)", active: true)
    }
}
