import SwiftUI

/// The home: the page's 3D model (with the card, its mood tint and notch, which the page still
/// draws) and over it the native controls, laid out where the web panel had them.
struct HomeSurface: View {
    enum Chrome {
        /// The popover under the menu bar icon: a card with a transparent margin for its shadow.
        case menubar
        /// The main window's Home: the page is the window.
        case window
    }

    let model: HomeModel
    let chrome: Chrome
    let onSlot: (WebSlotView, Bool) -> Void

    // The card's margin in the popover (`html.native #app` padding) and its corner.
    static let menubarInsets = EdgeInsets(top: 13, leading: 24, bottom: 34, trailing: 24)

    var body: some View {
        ZStack(alignment: .topLeading) {
            WebSlot(onPresence: onSlot)
            GeometryReader { geo in
                let insets = chrome == .menubar ? Self.menubarInsets : EdgeInsets()
                let card = CGSize(width: geo.size.width - insets.leading - insets.trailing,
                                  height: geo.size.height - insets.top - insets.bottom)
                Controls(model: model, card: card, wide: chrome == .window && geo.size.width >= 760)
                    .frame(width: card.width, height: card.height)
                    .opacity(model.pageError == nil ? 1 : 0)
                    .allowsHitTesting(model.pageError == nil)
                    .clipShape(RoundedRectangle(cornerRadius: chrome == .menubar ? 34 : 0, style: .continuous))
                    .offset(x: insets.leading, y: insets.top)
            }
        }
    }
}

/// The header over everything, and the device list or a sheet where the page's `.panel` was.
private struct Controls: View {
    let model: HomeModel
    let card: CGSize
    /// A wide window: the controls in a column beside the model instead of under it.
    let wide: Bool

    var body: some View {
        // style.css: `--stage-h: min(408px, 52%)`; the panel starts 34 px above the stage's end.
        let stage = min(408, card.height * 0.52)
        let side = min(440, card.width * 0.42)
        ZStack(alignment: .topLeading) {
            content
                .frame(width: wide ? side : card.width, height: wide ? card.height - 82 : card.height - (stage - 34))
                .overlay(alignment: .leading) {
                    if wide { Rectangle().fill(P.line).frame(width: 1).padding(.top, -82) }
                }
                .offset(x: wide ? card.width - side : 0, y: wide ? 82 : stage - 34)
            Header(model: model).frame(width: card.width)
            if let toast = model.toast {
                ToastView(toast: toast)
                    .allowsHitTesting(false)
                    .padding(16)
                    .frame(width: card.width, height: card.height, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .animation(P.ease(0.36), value: model.toast)
    }

    @ViewBuilder private var content: some View {
        ZStack(alignment: .top) {
            // The list scrolls all the way to the card's edge; its own padding keeps the last tile clear.
            DeviceList(model: model)
                .padding(.horizontal, 16)
                .opacity(model.sheet == nil ? 1 : 0)
                .scaleEffect(model.sheet == nil ? 1 : 0.985)
                .offset(y: model.sheet == nil ? 0 : 14)
                .allowsHitTesting(model.sheet == nil)
                .accessibilityHidden(model.sheet != nil)
            if let sheet = model.sheet {
                DeviceSheet(model: model, sheet: sheet)
                    .padding(.horizontal, 20).padding(.bottom, 18)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 26)),
                                            removal: .opacity.combined(with: .offset(y: 26))))
                    .id(sheet)
            }
        }
        .animation(P.ease(0.46), value: model.sheet)
    }
}

/// `.top`: the home's name and how much is on; the outside view, the floor plan menu and the
/// power button, which step aside while a sheet is open.
private struct Header: View {
    let model: HomeModel

    var body: some View {
        let detail = model.sheet != nil
        HStack(spacing: 10) {
            HStack(spacing: 11) {
                Icon("home", size: 17)
                    .foregroundStyle(Color(hex: "#cfe0ff"))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(P.glassHi))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(P.line))
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.config.name).font(.system(size: 16, weight: .semibold)).kerning(-0.16).foregroundStyle(P.text).lineLimit(1)
                    HStack(spacing: 6) {
                        LiveDot(on: model.anyOn)
                        (Text(model.lightsOn > 0 ? "\(model.lightsOn) of \(model.config.lights.count)" : "No").foregroundColor(P.text).fontWeight(.semibold)
                            + Text(" lights on")
                            + Text(model.houseTemp.map { " · " + AppModel.degrees($0) } ?? ""))
                            .lineLimit(1)
                    }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(P.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            Group {
                if model.agentLive { AIBadge { model.onAgentBadge?() } }
                RoundButton(icon: model.outside ? "door" : "trees", active: model.outside,
                            label: model.outside ? "Inside: the rooms" : "Outside: the house and its cameras") { model.toggleOutside() }
                RoundButton(icon: "settings", label: "Floor plan menu") { model.onGear?() }
                RoundButton(icon: "power", size: 46, iconSize: 21, stroke: 2.2, lit: model.anyOn, label: "Everything on / off") { model.toggleEverything() }
            }
            .opacity(detail ? 0 : 1)
            .scaleEffect(detail ? 0.8 : 1)
            .allowsHitTesting(!detail)
            .accessibilityHidden(detail)
        }
        .padding(.top, 20).padding(.leading, 22).padding(.trailing, 20)
        .animation(P.spring, value: detail)
    }
}

/// `.ai-badge`: an AI assistant has a live link; click to manage it.
private struct AIBadge: View {
    let action: () -> Void
    @StateObject private var glow = Hover()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Icon("sparkles", size: 13, stroke: 2.2)
                Text("AI").font(.system(size: 11.5, weight: .bold)).kerning(0.23)
            }
            .foregroundStyle(.white)
            .padding(.leading, 7).padding(.trailing, 9)
            .frame(height: 26)
            .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#7c5cff"), P.accent], startPoint: .leading, endPoint: .trailing)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            .background {
                // The halo breathes.
                Capsule().fill(Color(red: 124 / 255, green: 92 / 255, blue: 1).opacity(0.75))
                    .blur(radius: 6).padding(-5)
                    .opacity(glow.on ? 1 : 0.35)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glow.on)
            }
        }
        .buttonStyle(PressScale(scale: 0.93))
        .padding(.trailing, 2)
        .help("An AI assistant has access — click to manage")
        .accessibilityLabel("AI access")
        .onAppear { glow.on = true }
    }
}

/// `.panel-toast`: a device that refused a change, or what an AI assistant just did.
private struct ToastView: View {
    let toast: HomeModel.Toast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 9) {
            if let ai = toast.ai {
                HStack(spacing: 5) {
                    Icon("sparkles", size: 13, stroke: 2.2)
                    Text(ai)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.14)))
            }
            Text(toast.text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .lineSpacing(2)
        .foregroundStyle(toast.ai == nil ? Color(hex: "#ffd9d2") : Color(hex: "#eef0ff"))
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if toast.ai == nil {
                shape.fill(Color(red: 60 / 255, green: 20 / 255, blue: 22 / 255).opacity(0.92))
            } else {
                shape.fill(LinearGradient(colors: [Color(red: 58 / 255, green: 36 / 255, blue: 120 / 255).opacity(0.94),
                                                   Color(red: 28 / 255, green: 46 / 255, blue: 110 / 255).opacity(0.94)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay(shape.strokeBorder(toast.ai == nil ? Color(red: 1, green: 120 / 255, blue: 110 / 255).opacity(0.5)
                                                    : Color(red: 176 / 255, green: 150 / 255, blue: 1).opacity(0.5)))
        .shadow(color: toast.ai == nil ? .clear : Color(red: 120 / 255, green: 90 / 255, blue: 1).opacity(0.6), radius: 15, y: 10)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
