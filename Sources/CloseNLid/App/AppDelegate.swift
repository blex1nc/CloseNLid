import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    private let prefs = Preferences()
    private let status = AppStatus()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var ticker: Timer?
    private var tickerInterval: TimeInterval = 0
    /// Süreli moddaki bitiş anı. `nil` = süresiz.
    private var expiry: Date?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Yaşam döngüsü

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Sistemde uyku zaten kapalıysa (önceki oturum, çökme, başka bir araç)
        // durumu devral: kullanıcı buradan kapatabilmeli, aksi halde ayar
        // görünmez biçimde açık kalırdı.
        status.isActive = SleepGuard.isSystemSleepDisabled
        if status.isActive { SleepGuard.holdIdleAssertion() }

        status.ruleInstalled = Privilege.isRuleInstalled()
        status.launchAtLogin = LoginItem.isEnabled

        // Süre seçimi değişince sayaç baştan başlamalı. @Published willSet ile
        // yayınladığı için yeni değer prefs'ten değil, akıştan okunuyor.
        prefs.$duration
            .dropFirst()
            .sink { [weak self] value in self?.restartCountdown(with: value) }
            .store(in: &cancellables)

        refresh()
        retime()
        scheduleVisibilityCheck()

        // Geliştirme sondası: CloseNLid --probe
        if CommandLine.arguments.contains("--probe") {
            // Öğe hemen yerleşmiyor; bir tur beklemeden ölçmek yanlış sonuç verir.
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.probeStatusItem()
                    exit(0)
                }
            }
            return
        }

        // Geliştirme sondası: CloseNLid --settings [sleep|status|battery|thermal|access|general]
        if let index = CommandLine.arguments.firstIndex(of: "--settings") {
            let name = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : ""
            openSettings(pane: SettingsView.Pane(rawValue: name) ?? .sleep)
            return
        }
        openSetupIfNeeded()
    }

    /// Öğe menü çubuğuna hemen yerleşmiyor; ilk turda ölçmek yanlış sonuç verir.
    private func scheduleVisibilityCheck() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStatusItemVisibility() }
        }
    }

    /// İlk açılışta yetki kuralı yoksa ayarlar penceresi doğrudan Access
    /// bölmesinde açılır. Aksi halde uygulama menü çubuğunda sessizce duruyor,
    /// anahtar kilitli oluyor ve sebebi hiçbir yerde görünmüyor.
    private func openSetupIfNeeded() {
        let key = "hasSeenSetup"
        guard !status.ruleInstalled,
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        openSettings(pane: .access)
    }

    func applicationWillTerminate(_ notification: Notification) {
        SleepGuard.disableQuietly()
    }

    // MARK: - Durum çubuğu

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Sayaç yazısı her saniye değiştiği için sabit genişlikli rakam:
        // aksi halde menü çubuğundaki her şey yanıp sönerek kayıyor.
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        if thermalWarningActive {
            symbol = "exclamationmark.triangle.fill"
        } else {
            symbol = status.isActive ? "bolt.fill" : "bolt.slash"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "CloseNLid")
        button.image?.isTemplate = true
        // Kalan süre yalnızca süreli modda; süresizken yazı menü çubuğunda
        // gereksiz yer kaplıyor.
        button.title = status.isActive && status.remaining != nil
            ? " " + formatDuration(status.remaining ?? 0)
            : ""
    }

    /// Menü her açıldığında yeniden kurulur; başlıklar ve işaretler o anki
    /// duruma göre doğru olur.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        refresh()

        menu.addItem(label(headerTitle))
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Keep Awake", action: #selector(toggleActive), keyEquivalent: "")
        toggle.target = self
        toggle.state = status.isActive ? .on : .off
        toggle.isEnabled = status.ruleInstalled
        menu.addItem(toggle)

        let durations = NSMenuItem(title: "Turn Off After", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for option in KeepAwakeDuration.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(pickDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = prefs.duration == option ? .on : .off
            item.isEnabled = true
            submenu.addItem(item)
        }
        durations.submenu = submenu
        durations.isEnabled = true
        menu.addItem(durations)
        menu.addItem(.separator())

        menu.addItem(label("Lid: \(status.snapshot.lidTitle)"))
        menu.addItem(label("Power: \(status.snapshot.powerTitle)"))
        menu.addItem(label("Thermal: \(status.snapshot.thermalTitle)"))
        if thermalWarningActive {
            menu.addItem(label("Running hot with the lid closed"))
        }
        if !status.ruleInstalled {
            menu.addItem(.separator())
            let install = NSMenuItem(title: "Install Administrator Rule…",
                                     action: #selector(installRuleFromMenu), keyEquivalent: "")
            install.target = self
            install.isEnabled = true
            menu.addItem(install)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        settings.isEnabled = true
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit CloseNLid", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)
    }

    /// "Simge menü çubuğunda görünmüyor" şikayetinin sebebi neredeyse her zaman
    /// yer kalmaması oluyor: macOS öğeyi yine de yaratıyor ve görünür sayıyor,
    /// ama çentiğin altına yerleştirip gizliyor. Sonda bunu ayırt ediyor.
    private func probeStatusItem() {
        guard let button = statusItem?.button, let frame = button.window?.frame else {
            print("status item: not created")
            return
        }
        print("status item: x \(Int(frame.minX))…\(Int(frame.maxX)) pt, image \(button.image == nil ? "missing" : "ok")")
        if isStatusItemHidden {
            print("placement: HIDDEN behind the notch — the menu bar is full.")
            print("           Remove an icon, or ⌘-drag the others to make room.")
        } else {
            print("placement: visible in the menu bar")
        }
    }

    /// Öğe çentiğin altına düşmüş mü. macOS menü çubuğunda yer kalmadığında
    /// öğeyi silmiyor, `isVisible` hâlâ true diyor — sadece çentiğin arkasına
    /// koyuyor ve tıklanacak bir yer kalmıyor.
    private var isStatusItemHidden: Bool {
        guard let frame = statusItem?.button?.window?.frame,
              let screen = NSScreen.main,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return false }
        return !left.intersects(frame) && !right.intersects(frame)
    }

    /// Simge gizliyken uygulamaya ulaşmanın hiçbir yolu kalmıyor: ayarlar
    /// penceresi de yalnızca ilk açılışta kendiliğinden çıkıyor. Bunu bir kez
    /// söylemek gerekiyor, yoksa uygulama hiç açılmamış gibi duruyor.
    private func checkStatusItemVisibility() {
        let key = "hasWarnedHiddenIcon"
        let defaults = UserDefaults.standard
        guard isStatusItemHidden else {
            defaults.set(false, forKey: key)
            return
        }
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        alert("The menu bar is full",
              "macOS placed the CloseNLid icon behind the notch, so there is nothing to click. Remove another menu bar icon — or ⌘-drag the icons to rearrange them — and it will appear. Settings can be reopened from there.")
    }

    /// Tıklanamayan bilgi satırı.
    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private var headerTitle: String {
        guard status.isActive else { return "Normal sleep" }
        guard let remaining = status.remaining else { return "Awake with the lid closed" }
        return "Awake — \(formatDuration(remaining)) left"
    }

    // MARK: - Anahtar

    private func setActive(_ enabled: Bool) {
        status.message = nil
        do {
            if enabled {
                // Eşiğin altındayken açmak anlamsız: koruma bir sonraki turda
                // kapatırdı ve anahtar kendiliğinden geri düşmüş gibi görünürdü.
                if prefs.batteryGuardEnabled, batteryBelowThreshold {
                    status.message = "Battery is at \(status.snapshot.batteryPercent)%, at or below the \(prefs.batteryThreshold)% guard. Plug in or lower the threshold first."
                    refresh()
                    return
                }
                try SleepGuard.enable()
                status.isActive = true
                restartCountdown(with: prefs.duration)
            } else {
                try SleepGuard.disable()
                status.isActive = false
                expiry = nil
                status.remaining = nil
            }
        } catch {
            status.message = error.localizedDescription
            status.ruleInstalled = Privilege.isRuleInstalled()
            status.isActive = SleepGuard.isSystemSleepDisabled
        }
        refresh()
        retime()
    }

    private func restartCountdown(with duration: KeepAwakeDuration) {
        guard status.isActive else {
            expiry = nil
            status.remaining = nil
            return
        }
        expiry = duration.seconds.map { Date().addingTimeInterval($0) }
        refresh()
        retime()
    }

    // MARK: - Tur

    /// Sayaç görünürken saniyede bir, aksi halde beş saniyede bir. Uykuyu
    /// engelleyen bir uygulamanın kendisi boşuna CPU uyandırmamalı.
    private func retime() {
        let wanted: TimeInterval = (status.isActive && expiry != nil)
            || (settingsWindow?.isVisible ?? false) ? 1 : 5
        guard wanted != tickerInterval else { return }
        tickerInterval = wanted
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: wanted, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
    }

    private func onTick() {
        refresh()
        checkStatusItemVisibility()
        checkExpiry()
        checkBatteryGuard()
        checkThermalStop()
    }

    private func refresh() {
        status.snapshot = SystemInfo.snapshot()
        status.ruleInstalled = Privilege.isRuleInstalled()

        // Sistem durumu bizden bağımsız değiştiyse hizala.
        if status.isActive != status.snapshot.sleepDisabled {
            status.isActive = status.snapshot.sleepDisabled
            if !status.isActive {
                expiry = nil
                status.remaining = nil
            }
        }
        status.remaining = status.isActive ? expiry.map { max(0, $0.timeIntervalSinceNow) } : nil
        updateStatusItem()
    }

    private func checkExpiry() {
        guard status.isActive, let expiry, Date() >= expiry else { return }
        setActive(false)
        status.message = "The timer finished, so the sleep block was switched off."
    }

    private var batteryBelowThreshold: Bool {
        status.snapshot.hasBattery
            && !status.snapshot.onExternalPower
            && status.snapshot.batteryPercent <= prefs.batteryThreshold
    }

    private func checkBatteryGuard() {
        guard status.isActive, prefs.batteryGuardEnabled, batteryBelowThreshold else { return }
        let level = status.snapshot.batteryPercent
        setActive(false)
        status.message = "Battery reached \(level)% — the sleep block was switched off."
        alert("Sleep block switched off",
              "The battery dropped to \(level)%. With the lid closed there is no low-battery warning to see, so CloseNLid handed the Mac back to normal sleep before the charge ran out.")
    }

    private var thermalWarningActive: Bool {
        status.isActive
            && prefs.thermalWarningEnabled
            && status.snapshot.thermalRank >= prefs.thermalTrigger.rank
    }

    private func checkThermalStop() {
        guard status.isActive, prefs.stopWhenCritical, status.snapshot.thermalRank >= 3 else { return }
        setActive(false)
        status.message = "Thermals went critical — the sleep block was switched off."
        alert("Sleep block switched off",
              "The Mac reached a critical thermal state. Closed-lid airflow is limited, so CloseNLid switched the block off to let it cool down.")
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        // .accessory politikasında uyarı kendiliğinden öne gelmez.
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menü eylemleri

    @objc private func toggleActive() { setActive(!status.isActive) }

    @objc private func pickDuration(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = KeepAwakeDuration(rawValue: raw) else { return }
        prefs.duration = option
    }

    @objc private func installRuleFromMenu() { installRule() }

    @objc private func quit() { NSApp.terminate(nil) }

    private func installRule() {
        do {
            try Privilege.installRule()
            status.message = "Administrator rule installed."
        } catch {
            status.message = error.localizedDescription
        }
        status.ruleInstalled = Privilege.isRuleInstalled()
        refresh()
    }

    private func removeRule() {
        // Kural gidince uyku engeli kapatılamaz hale gelir; önce kapat.
        if status.isActive { setActive(false) }
        do {
            try Privilege.removeRule()
            status.message = "Administrator rule removed."
        } catch {
            status.message = error.localizedDescription
        }
        status.ruleInstalled = Privilege.isRuleInstalled()
        refresh()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let failure = LoginItem.setEnabled(enabled)
        status.loginItemMessage = failure
        // Gerçekleşen durumu oku; kayıt başarısızsa anahtar geri dönmeli.
        status.launchAtLogin = failure == nil ? enabled : LoginItem.isEnabled
    }

    // MARK: - Ayarlar penceresi

    @objc private func openSettingsFromMenu() { openSettings(pane: nil) }

    private func openSettings(pane: SettingsView.Pane?) {
        if let existing = settingsWindow {
            status.ruleInstalled = Privilege.isRuleInstalled()
            status.launchAtLogin = LoginItem.isEnabled
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            retime()
            return
        }

        let view = SettingsView(
            prefs: prefs,
            status: status,
            actions: SettingsActions(
                setActive: { [weak self] in self?.setActive($0) },
                setLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin($0) },
                installRule: { [weak self] in self?.installRule() },
                removeRule: { [weak self] in self?.removeRule() },
                openEnergySettings: { Self.openEnergySettings() }
            ),
            initialPane: pane
        )
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "CloseNLid Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        // .accessory politikasında pencere kendiliğinden öne gelmez.
        NSApp.activate(ignoringOtherApps: true)
        retime()
    }

    /// Pencere kapanınca sayaç tekrar yavaşlasın.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.retime() }
    }

    private static func openEnergySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") else { return }
        NSWorkspace.shared.open(url)
    }
}
