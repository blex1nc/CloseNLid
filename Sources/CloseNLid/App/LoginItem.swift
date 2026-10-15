import Foundation
import ServiceManagement

/// "Girişte başlat" ayarının sarmalayıcısı.
///
/// `SMAppService` gerçek bir uygulama paketi ister. Geliştirme sırasında ham
/// SwiftPM ikilisi çalıştırıldığında kayıt başarısız olur; bu beklenen bir durum
/// ve kullanıcıya hata olarak gösterilmez — ayar `.app` içinden çalıştırıldığında
/// düzgün işler.
enum LoginItem {

    static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        guard isBundled else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Başarılıysa `nil`, aksi halde kullanıcıya gösterilecek mesaj döner.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard isBundled else {
            return "Launch at login only works when running the installed app."
        }
        do {
            if enabled {
                // Zaten kayıtlıyken tekrar register çağırmak hata verir.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
