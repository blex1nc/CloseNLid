import SwiftUI

/// Uygulama durumunun ayarlar penceresine yansıyan, kalıcı olmayan kısmı.
@MainActor
final class AppStatus: ObservableObject {
    /// Uyku engeli şu an açık mı.
    @Published var isActive = false
    /// Süreli moddaysa kalan zaman, değilse nil.
    @Published var remaining: TimeInterval?
    @Published var snapshot = SystemSnapshot()
    /// sudoers kuralı kurulu mu. Alt süreç açtığı için sürekli değil,
    /// yalnızca gerektiğinde tazeleniyor.
    @Published var ruleInstalled = false
    @Published var launchAtLogin = false
    @Published var loginItemMessage: String?
    /// Son işlemin sonucu: kurulum, hata ya da otomatik kapanma sebebi.
    @Published var message: String?
}

struct SettingsActions {
    var setActive: (Bool) -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var installRule: () -> Void
    var removeRule: () -> Void
    var openEnergySettings: () -> Void
}

/// Ayarlar penceresi. Tüm kullanıcı metinleri İngilizce.
struct SettingsView: View {

    @ObservedObject var prefs: Preferences
    @ObservedObject var status: AppStatus
    var actions: SettingsActions
    /// Menüden belirli bir bölmeye gidilebilsin diye. Normalde nil.
    var initialPane: Pane?

    /// Kenar çubuğundaki bölümler.
    enum Pane: String, CaseIterable, Identifiable {
        case sleep, status, battery, thermal, access, general

        var id: String { rawValue }

        /// Kullanıcıya görünen metin — İngilizce.
        var title: String {
            switch self {
            case .sleep:   return "Sleep"
            case .status:  return "Status"
            case .battery: return "Battery"
            case .thermal: return "Thermal"
            case .access:  return "Access"
            case .general: return "General"
            }
        }

        var symbol: String {
            switch self {
            case .sleep:   return "bolt.fill"
            case .status:  return "laptopcomputer"
            case .battery: return "battery.100percent"
            case .thermal: return "thermometer.medium"
            case .access:  return "lock.shield"
            case .general: return "gearshape"
            }
        }

        /// Çipin rengi. Simgeler tek renk olduğunda kenar çubuğu gri bir listeye
        /// dönüşüyor ve göz sırayı ezberleyemiyor; renk her satıra bir tutamak
        /// veriyor. Sistemin kendi Ayarlar penceresindeki dil de bu.
        var color: Color {
            switch self {
            case .sleep:   return .blue
            case .status:  return .indigo
            case .battery: return .green
            case .thermal: return .orange
            case .access:  return .pink
            case .general: return .gray
            }
        }
    }

    /// Altı satır düz bir liste olarak da dururdu ama başlıklar aradığın şeyi
    /// bir bakışta daraltıyor.
    private static let groups: [(title: String?, panes: [Pane])] = [
        (nil, [.sleep, .status]),
        ("Safety", [.battery, .thermal]),
        ("System", [.access, .general]),
    ]

    @State private var pane: Pane = .sleep

    /// Paketten okunan sürüm. Elle yazılan bir dize `Scripts/bundle.sh`'deki
    /// sürümle ayrı ayrı güncellenmek zorunda kalır ve biri sessizce geride
    /// kalır. Paketlenmemiş çalıştırmada anahtar yok.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// Üstte sekme şeridi yerine solda kenar çubuğu: altı sekme şeride sıkışınca
    /// etiketler kısalıyor ve pencere kendi içeriğinden dar görünüyordu. Sistemin
    /// kendi Ayarlar penceresi de aynı düzeni kullanıyor.
    ///
    /// `NavigationSplitView` yerine elle kurulmuş: bu pencere bir SwiftUI sahnesi
    /// değil, `NSHostingController` içindeki düz bir `NSWindow`. Orada bölünmüş
    /// görünüm kendi araç çubuğunu ve daraltma düğmesini getiriyor, ikisi de
    /// burada anlamsız.
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 660, height: 580)
        .onAppear { if let initialPane { pane = initialPane } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("CloseNLid")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ForEach(Array(Self.groups.enumerated()), id: \.offset) { _, group in
                if let title = group.title {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 15)
                        .padding(.top, 14)
                        .padding(.bottom, 5)
                }
                ForEach(group.panes) { item in
                    row(item)
                }
            }

            Spacer(minLength: 0)

            // Kenar çubuğunun dibindeki canlı özet: hangi bölmede olursan ol
            // uyku engelinin açık olup olmadığı görünür kalmalı.
            HStack(spacing: 7) {
                Circle()
                    .fill(status.isActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(status.isActive ? "Awake" : "Normal sleep")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.bottom, 14)
        }
        .frame(width: 186)
        .background(.regularMaterial)
    }

    private func row(_ item: Pane) -> some View {
        let isSelected = pane == item
        return Button {
            pane = item
        } label: {
            HStack(spacing: 9) {
                // Renkli çip: beyaz simge, yuvarlatılmış kare.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(item.color)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: item.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(item.title)
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background {
                // Vurgu mavisi yerine hafif gri: çipler zaten renkli, seçili
                // satırı da boyamak kenar çubuğunu karnavala çeviriyordu.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.09 : 0))
            }
            // Etiketin tamamı tıklanabilir olmalı, yalnızca yazı değil.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .sleep:   sleepTab
        case .status:  statusTab
        case .battery: batteryTab
        case .thermal: thermalTab
        case .access:  accessTab
        case .general: generalTab
        }
    }

    // MARK: - Uyku

    private var sleepTab: some View {
        Form {
            Section("Keep awake") {
                Toggle("Stay awake with the lid closed", isOn: Binding(
                    get: { status.isActive },
                    set: { actions.setActive($0) }
                ))
                .disabled(!status.ruleInstalled)

                Text("Closing the lid stops suspending the Mac. The screen still switches off, so downloads, renders and servers keep running in a bag or under a monitor — no external display or dock required.")
                    .font(.caption).foregroundStyle(.secondary)

                // Anahtar kilitliyse sebebi burada yazmazsak bozuk sanılır.
                if !status.ruleInstalled {
                    Label("Install the administrator rule in the Access pane first.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Duration") {
                Picker("Turn off after", selection: $prefs.duration) {
                    ForEach(KeepAwakeDuration.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(prefs.duration.subtitle)
                    .font(.caption).foregroundStyle(.secondary)

                if let remaining = status.remaining {
                    LabeledContent("Time left", value: formatDuration(remaining))
                }
            }

            Section("How it works") {
                Text("macOS is told not to sleep at all, and an idle-sleep assertion is held alongside it. Both are lifted the moment you switch this off, when the timer runs out, when the battery guard trips, or when the app quits.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Command", value: "pmset -a disablesleep")
            }

            if let message = status.message {
                Section("Last action") {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Durum

    private var statusTab: some View {
        Form {
            Section("Right now") {
                LabeledContent("Lid", value: status.snapshot.lidTitle)
                LabeledContent("Sleep", value: status.snapshot.sleepDisabled ? "Blocked" : "Normal")
                LabeledContent("Power", value: status.snapshot.powerTitle)
                LabeledContent("Thermal", value: status.snapshot.thermalTitle)
            }

            Section("Watch out for") {
                // Uyarılar yalnızca gerçekten geçerliyken çıkıyor; boş bir uyarı
                // listesi zamanla görünmez oluyor.
                if status.isActive && !status.snapshot.onExternalPower && status.snapshot.hasBattery {
                    warning("Running on battery with sleep blocked. The Mac will keep draining until the battery guard trips.")
                }
                if status.isActive && status.snapshot.lidClosed && status.snapshot.thermalRank >= 2 {
                    warning("The lid is closed and the Mac is hot. Airflow is restricted in this position.")
                }
                if !status.isActive && status.snapshot.sleepDisabled {
                    warning("Something else on this Mac is blocking sleep — the setting is on but this app did not switch it.")
                }
                if healthy {
                    Label("Nothing to flag.", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Sources") {
                Text("Lid and sleep state are read from IOPMrootDomain, power from IOKit's power sources, and the thermal reading is the same one macOS gives every app. None of it needs a password.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Energy settings", action: actions.openEnergySettings)
            }
        }
        .formStyle(.grouped)
    }

    private var healthy: Bool {
        let battery = status.isActive && !status.snapshot.onExternalPower && status.snapshot.hasBattery
        let hot = status.isActive && status.snapshot.lidClosed && status.snapshot.thermalRank >= 2
        let stray = !status.isActive && status.snapshot.sleepDisabled
        return !battery && !hot && !stray
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange)
    }

    // MARK: - Pil

    private var batteryTab: some View {
        Form {
            Section("Battery guard") {
                Toggle("Turn the sleep block off when the battery runs low",
                       isOn: $prefs.batteryGuardEnabled)

                LabeledContent("Threshold") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(prefs.batteryThreshold) },
                            set: { prefs.batteryThreshold = Int($0) }
                        ), in: 5...50, step: 5)
                        Text("\(prefs.batteryThreshold)%")
                            .foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                .disabled(!prefs.batteryGuardEnabled)

                Text("Only applies on battery power. With the lid shut the screen is dark, so a Mac left awake in a bag drains to nothing without ever showing a low-battery warning — this is the thing that stops it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Current") {
                LabeledContent("Power", value: status.snapshot.powerTitle)
                if status.snapshot.hasBattery {
                    ProgressView(value: Double(status.snapshot.batteryPercent), total: 100)
                    if prefs.batteryGuardEnabled && !status.snapshot.onExternalPower {
                        Text(status.snapshot.batteryPercent <= prefs.batteryThreshold
                             ? "At or below the threshold — the sleep block cannot stay on."
                             : "\(status.snapshot.batteryPercent - prefs.batteryThreshold)% of headroom before the guard trips.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("No internal battery on this Mac, so the guard has nothing to watch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("When it trips") {
                Text("The sleep block is switched off and an alert says why. Nothing is force-quit and nothing is put to sleep by the app — macOS simply goes back to its normal behaviour.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Isı

    private var thermalTab: some View {
        Form {
            Section("Heat warning") {
                Toggle("Warn when the Mac runs hot", isOn: $prefs.thermalWarningEnabled)

                Picker("Warn at", selection: $prefs.thermalTrigger) {
                    ForEach(ThermalTrigger.allCases) { trigger in
                        Text(trigger.title).tag(trigger)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!prefs.thermalWarningEnabled)

                Text(prefs.thermalTrigger.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                Text("A closed lid blocks the vents and puts the keyboard deck against whatever the Mac is resting on, so heat that would be fine with the lid open is worth knowing about here.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Automatic stop") {
                Toggle("Turn the sleep block off if thermals go critical",
                       isOn: $prefs.stopWhenCritical)
                Text("Off by default — a long export should not be cut short just because the Mac got warm. Turn it on if the machine spends its closed-lid time somewhere with no airflow.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Current") {
                LabeledContent("Thermal state", value: status.snapshot.thermalTitle)
                LabeledContent("Lid", value: status.snapshot.lidTitle)
                if prefs.thermalWarningEnabled && status.snapshot.thermalRank >= prefs.thermalTrigger.rank {
                    warning("Above your warning threshold right now.")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Yetki

    private var accessTab: some View {
        Form {
            Section("Administrator rule") {
                LabeledContent("Status", value: status.ruleInstalled ? "Installed" : "Not installed")

                Text("Blocking lid sleep is a system-level change, so it needs root. Rather than asking for your password on every switch, a one-time rule in /etc/sudoers.d/closenlid lets this app run two exact commands — and nothing else — without a prompt.")
                    .font(.caption).foregroundStyle(.secondary)

                if status.ruleInstalled {
                    Button("Remove Rule…", role: .destructive, action: actions.removeRule)
                } else {
                    Button("Install Rule…", action: actions.installRule)
                }

                if let message = status.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("What gets written") {
                Text(Privilege.ruleLine)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The file is validated with visudo before it is installed — a malformed rule would break sudo for the whole machine, so it never gets copied unless it parses.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Removing it") {
                Text("Remove Rule deletes the file and puts the password prompt back. You can also delete it by hand:")
                    .font(.caption).foregroundStyle(.secondary)
                Text("sudo rm \(Privilege.sudoersPath)")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Genel

    private var generalTab: some View {
        Form {
            Section("About") {
                LabeledContent("CloseNLid", value: Self.appVersion)
                Text("Keeps a Mac running with the lid closed, with no external display attached.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { status.launchAtLogin },
                    set: { actions.setLaunchAtLogin($0) }
                ))
                Text("The app starts in the menu bar with the sleep block off. It is never switched on for you.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = status.loginItemMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("On quit") {
                Text("Quitting restores normal sleep behaviour first. If the app is ever killed while the block is on, the setting survives — reopen the app and it will show as on so you can switch it off.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: Self.appVersion)
                Text("Nothing is sent anywhere. The app talks to macOS power management and nothing else.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
