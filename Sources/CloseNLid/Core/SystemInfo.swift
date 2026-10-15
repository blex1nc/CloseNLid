import Foundation
import IOKit
import IOKit.ps

/// IOPMrootDomain'den okunan, root gerektirmeyen sistem bayrakları.
enum IORegistry {

    static func bool(_ key: String) -> Bool? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue()
        else { return nil }
        if let flag = value as? Bool { return flag }
        if let number = value as? Int { return number != 0 }
        return nil
    }
}

/// Bir andaki sistem durumu. Tek parça olarak yayınlanıyor ki arayüz yarım
/// güncellenmiş bir karışım göstermesin.
struct SystemSnapshot: Equatable {

    var batteryPercent = 100
    var onExternalPower = true
    var hasBattery = true
    var lidClosed = false
    var thermal: ProcessInfo.ThermalState = .nominal
    var sleepDisabled = false

    /// Kullanıcıya görünen metin — İngilizce.
    var thermalTitle: String {
        switch thermal {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var lidTitle: String { lidClosed ? "Closed" : "Open" }

    var powerTitle: String {
        guard hasBattery else { return "Power adapter" }
        return (onExternalPower ? "Power adapter" : "Battery") + " · \(batteryPercent)%"
    }

    /// Sıralı karşılaştırma yapabilmek için: uyarı eşiği bir seçim kutusundan
    /// geliyor ve "bundan yüksekse" diye sorulması gerekiyor.
    var thermalRank: Int {
        switch thermal {
        case .nominal:  return 0
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }
}

enum SystemInfo {

    static func snapshot() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.lidClosed = IORegistry.bool("AppleClamshellState") ?? false
        snapshot.sleepDisabled = IORegistry.bool("SleepDisabled") ?? false
        snapshot.thermal = ProcessInfo.processInfo.thermalState
        if let power = readPower() {
            snapshot.batteryPercent = power.percent
            snapshot.onExternalPower = power.onExternalPower
        } else {
            // Masaüstü Mac ya da pil okunamıyor: pil koruması anlamsız.
            snapshot.hasBattery = false
        }
        return snapshot
    }

    private static func readPower() -> (percent: Int, onExternalPower: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey as String] as? String) == (kIOPSInternalBatteryType as String)
            else { continue }

            let current = info[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maximum = info[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let external = (info[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0
            return (percent, external)
        }
        return nil
    }
}
