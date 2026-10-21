import Foundation

/// What the Mac island's right ear shows at rest, after a peek (which always wins): a running AC,
/// or what the solar panels make. Neither: the island says "Off" around a real notch, or nothing.
public enum IslandEar: Equatable, Sendable {
    case ac
    /// The production, as written ("3.2 kW").
    case solar(String)

    /// The setting: an AC first and then the sun (Auto), only an AC, or the sun first.
    public enum Choice: String, CaseIterable, Sendable {
        case auto, ac, solar
    }

    /// `production`: what the panels make when it is worth a look (`HomeConfig.Energy.production`).
    public static func resting(_ choice: Choice, acRunning: Bool, production: String?) -> IslandEar? {
        let sun = production.map(IslandEar.solar)
        switch choice {
        case .auto: return acRunning ? .ac : sun
        case .ac: return acRunning ? .ac : nil
        case .solar: return sun ?? (acRunning ? .ac : nil)
        }
    }
}
