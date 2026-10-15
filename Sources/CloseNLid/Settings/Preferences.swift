import Foundation

/// Uyku engelinin kendini kapatacağı süre.
enum KeepAwakeDuration: String, CaseIterable, Identifiable {
    case indefinite
    case thirtyMinutes
    case oneHour
    case twoHours

    var id: String { rawValue }

    /// Kullanıcıya görünen metin — İngilizce.
    var title: String {
        switch self {
        case .indefinite:    return "Indefinite"
        case .thirtyMinutes: return "30 min"
        case .oneHour:       return "1 hour"
        case .twoHours:      return "2 hours"
        }
    }

    /// `nil` = kendiliğinden kapanmaz.
    var seconds: TimeInterval? {
        switch self {
        case .indefinite:    return nil
        case .thirtyMinutes: return 30 * 60
        case .oneHour:       return 60 * 60
        case .twoHours:      return 2 * 60 * 60
        }
    }

    var subtitle: String {
        switch self {
        case .indefinite:
            return "Stays on until you turn it off or quit the app."
        default:
            return "Turns itself off after \(title.lowercased()), so a forgotten switch cannot drain the battery overnight."
        }
    }
}

/// Isı uyarısının tetikleneceği eşik. `ProcessInfo.ThermalState` sırasıyla
/// eşleşiyor; nominal bir eşik değil, uyarı için anlamsız.
enum ThermalTrigger: String, CaseIterable, Identifiable {
    case fair
    case serious
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        }
    }

    var rank: Int {
        switch self {
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        }
    }

    var subtitle: String {
        switch self {
        case .fair:
            return "Earliest warning — the fans are up but nothing is throttled yet."
        case .serious:
            return "macOS has started throttling to shed heat."
        case .critical:
            return "Last stop before the Mac takes emergency measures."
        }
    }
}

final class Preferences: ObservableObject {

    private let defaults = UserDefaults.standard

    @Published var duration: KeepAwakeDuration {
        didSet { defaults.set(duration.rawValue, forKey: Keys.duration) }
    }
    /// Fişten çekiliyken pil eşiğin altına düşerse uyku engeli kapanır.
    @Published var batteryGuardEnabled: Bool {
        didSet { defaults.set(batteryGuardEnabled, forKey: Keys.batteryGuardEnabled) }
    }
    /// Yüzde. Kapalı kapakta ekran karanlık olduğu için pilin bittiği fark
    /// edilmiyor; varsayılan bilerek yüksek tutuluyor.
    @Published var batteryThreshold: Int {
        didSet { defaults.set(batteryThreshold, forKey: Keys.batteryThreshold) }
    }
    @Published var thermalWarningEnabled: Bool {
        didSet { defaults.set(thermalWarningEnabled, forKey: Keys.thermalWarningEnabled) }
    }
    @Published var thermalTrigger: ThermalTrigger {
        didSet { defaults.set(thermalTrigger.rawValue, forKey: Keys.thermalTrigger) }
    }
    /// Kritik sıcaklıkta uyku engelini kendiliğinden kapat. Varsayılan kapalı:
    /// uzun bir işi ısındı diye yarıda kesmek herkesin isteyeceği şey değil.
    @Published var stopWhenCritical: Bool {
        didSet { defaults.set(stopWhenCritical, forKey: Keys.stopWhenCritical) }
    }

    init() {
        duration = KeepAwakeDuration(rawValue: defaults.string(forKey: Keys.duration) ?? "") ?? .indefinite
        batteryGuardEnabled = defaults.object(forKey: Keys.batteryGuardEnabled) as? Bool ?? true
        batteryThreshold = defaults.object(forKey: Keys.batteryThreshold) as? Int ?? 20
        thermalWarningEnabled = defaults.object(forKey: Keys.thermalWarningEnabled) as? Bool ?? true
        thermalTrigger = ThermalTrigger(rawValue: defaults.string(forKey: Keys.thermalTrigger) ?? "") ?? .serious
        stopWhenCritical = defaults.object(forKey: Keys.stopWhenCritical) as? Bool ?? false
    }

    private enum Keys {
        static let duration = "duration"
        static let batteryGuardEnabled = "batteryGuardEnabled"
        static let batteryThreshold = "batteryThreshold"
        static let thermalWarningEnabled = "thermalWarningEnabled"
        static let thermalTrigger = "thermalTrigger"
        static let stopWhenCritical = "stopWhenCritical"
    }
}

/// Saniyeyi `1:02:03` / `4:07` biçiminde yazar.
func formatDuration(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}
