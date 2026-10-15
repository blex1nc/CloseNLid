import Foundation
import IOKit.pwr_mgt

/// Uyku engeli iki katmanlı:
///
/// 1. IOPM assertion — boşta kalma uykusunu engeller, yetki istemez ve süreç
///    ölürse kendiliğinden düşer.
/// 2. `pmset disablesleep` — kapağın kapanmasıyla gelen uykuyu da engeller.
///    Root ister ve sistem genelinde kalıcıdır; bu yüzden çıkışta geri alınır.
///
/// Tek başına assertion yetmiyor: kapak kapanışı assertion'ları dinlemez.
enum SleepGuard {

    private static var assertionID: IOPMAssertionID = 0
    private static var holdsAssertion = false

    /// Sistemdeki gerçek durum. Uygulama dışında (önceki oturum, çökme, başka
    /// bir araç) değişmiş olabileceği için tek doğru kaynak burası.
    static var isSystemSleepDisabled: Bool {
        IORegistry.bool("SleepDisabled") ?? false
    }

    static func enable() throws {
        try Privilege.setDisableSleep(true)
        holdIdleAssertion()
    }

    static func disable() throws {
        releaseIdleAssertion()
        try Privilege.setDisableSleep(false)
    }

    /// Uygulama kapanırken çağrılır. Hata yutuluyor; amaç sistemi normal uyku
    /// davranışıyla bırakmak, kullanıcıyı çıkışta uyarmak değil.
    static func disableQuietly() {
        releaseIdleAssertion()
        try? Privilege.setDisableSleep(false)
    }

    static func holdIdleAssertion() {
        guard !holdsAssertion else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "CloseNLid is keeping this Mac awake" as CFString,
            &assertionID)
        holdsAssertion = result == kIOReturnSuccess
    }

    static func releaseIdleAssertion() {
        guard holdsAssertion else { return }
        IOPMAssertionRelease(assertionID)
        holdsAssertion = false
        assertionID = 0
    }
}
