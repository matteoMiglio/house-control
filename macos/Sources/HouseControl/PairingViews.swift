import SwiftUI
import HouseCore

/// A QR code on a white card: scanners need the quiet zone around it.
struct QRCard: View {
    let content: String

    var body: some View {
        Group {
            if let image = QRCode.image(for: content, scale: 12) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
            } else {
                Color.clear
            }
        }
        .padding(18)
        .frame(width: 268, height: 268)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A line of status under a code: a dot (green while something is connected) and a sentence.
struct StatusLine: View {
    let text: String
    let active: Bool

    var body: some View {
        if !text.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle().fill(active ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                Text(text).font(.callout.weight(.medium)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)
        }
    }
}

/// Pair iPhone: the code an iPhone scans once to find this Mac and keep the home in sync.
struct PairingView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Scan with House Control on your iPhone").font(.title3.weight(.semibold))
                if let link = model.pairingLink { QRCard(content: link) }
                Text("On the iPhone open Settings → Pair with Mac. Both devices must be on the same Wi-Fi. Your floor plan, device links and connections stay the same on both, whichever one you edit; they travel straight between them, encrypted with the key in this code.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                StatusLine(text: model.pairingStatus.text, active: model.pairingStatus.active)
                HStack(spacing: 10) {
                    Button("Copy Pairing Link") { model.copyPairingLink() }
                    Button("Reset Pairing…") { model.resetPairing() }
                }
                .controlSize(.large)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Pair iPhone")
        .onAppear { model.enablePairing() }
    }
}

/// The Smart Life login code a paired iPhone asked this Mac to show, for the Smart Life app on
/// that phone to scan.
struct PhoneLoginView: View {
    let content: String
    let device: String

    var body: some View {
        VStack(spacing: 18) {
            Text("Scan with the Smart Life app on \(device)").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            QRCard(content: content)
            Text("Switch to Smart Life on the iPhone, tap the scanner on its Home tab and confirm the login. Then return to House Control: this window closes once the iPhone is signed in.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
            StatusLine(text: "Requested by \(device)", active: true)
        }
        .padding(EdgeInsets(top: 46, leading: 30, bottom: 26, trailing: 30))
        .frame(width: 380)
    }
}
