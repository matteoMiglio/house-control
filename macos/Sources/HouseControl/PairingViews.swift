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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(active ? Theme.green : Theme.faint).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(text).font(.callout.weight(.medium)).foregroundStyle(active ? Theme.text : Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity) // centred, like the code and the buttons around it
        }
    }
}

/// Pair iPhone: the code an iPhone scans once to find this Mac and keep the home in sync.
struct PairingView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Pair iPhone").font(.system(size: 28, weight: .bold))
                    Text("Your home, in sync on your Mac and iPhone.")
                        .font(.callout).foregroundStyle(Theme.muted)
                }
                .multilineTextAlignment(.center)

                if let link = model.pairingLink { QRCard(content: link) }

                VStack(spacing: 10) {
                    SectionTitle("How to pair")
                    Card(padding: 18) {
                        VStack(alignment: .leading, spacing: 16) {
                            PairingStep(number: 1, text: "Open House Control on your iPhone.")
                            PairingStep(number: 2, text: "Go to Settings → Pair with Mac.")
                            PairingStep(number: 3, text: "Point the camera at this code.")
                        }
                    }
                    Text("Keep both devices on the same Wi-Fi. Your floor plan and connections sync directly, encrypted with the key in this code.")
                        .font(.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }

                StatusLine(text: model.pairingStatus.text, active: model.pairingStatus.active)

                HStack(spacing: 12) {
                    Button { model.copyPairingLink() } label: {
                        Label("Copy Pairing Link", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reset Pairing…", role: .destructive) { model.resetPairing() }
                        .buttonStyle(.bordered).tint(Theme.red).foregroundStyle(Theme.red)
                }
                .controlSize(.large)
            }
            .frame(maxWidth: 440)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .background(Theme.background)
        .navigationTitle("Pair iPhone")
        .onAppear { model.enablePairing() }
    }
}

/// A numbered instruction beside the code.
private struct PairingStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accent.opacity(0.16), in: Circle())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The Smart Life login code a paired iPhone asked this Mac to show, for the Smart Life app on
/// that phone to scan.
struct PhoneLoginView: View {
    let content: String
    let device: String

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Sign in to Smart Life").font(.title2.weight(.bold))
                Text("Scan with Smart Life on \(device).")
                    .font(.callout).foregroundStyle(Theme.muted)
            }
            .multilineTextAlignment(.center)
            QRCard(content: content)
            Card(padding: 16) {
                Text("Open Smart Life, tap the scanner on its Home tab and confirm the login. Return to House Control when you're done; this window closes once you're signed in.")
                    .font(.callout).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StatusLine(text: "Requested by \(device)", active: true)
        }
        .foregroundStyle(Theme.text)
        .padding(EdgeInsets(top: 46, leading: 30, bottom: 26, trailing: 30))
        .frame(width: 380)
        .background(Theme.background)
    }
}
