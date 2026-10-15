import Foundation

/// Kapak kapalıyken uykuyu engellemenin tek ayrıcalıklı adımı:
/// `pmset -a disablesleep 0|1`. Root ister.
///
/// Her açma/kapamada şifre sormak yerine tek seferlik bir sudoers kuralı
/// yazılıyor. Kural yalnızca bu iki tam komutu kapsıyor; joker yok, başka
/// hiçbir şey şifresiz çalışmıyor.
enum Privilege {

    static let sudoersPath = "/etc/sudoers.d/closenlid"
    static let pmsetPath = "/usr/bin/pmset"
    private static let sudoPath = "/usr/bin/sudo"

    /// Kurulacak satır. Ayarlar penceresi bunu olduğu gibi gösteriyor —
    /// kullanıcı neye onay verdiğini görebilmeli.
    static var ruleLine: String {
        "\(NSUserName()) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 1, \(pmsetPath) -a disablesleep 0"
    }

    enum Failure: LocalizedError {
        case notAuthorized
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "The administrator rule is not installed yet."
            case .cancelled:
                return "Authorisation was cancelled."
            case .failed(let message):
                return message.isEmpty ? "The command failed." : message
            }
        }
    }

    /// Kural yerinde mi? Dosyanın varlığına bakılıyor: `/etc/sudoers.d`
    /// dünyaya okunabilir (0755), içindeki dosya değil — varlık sorusu için
    /// bu yeter ve alt süreç gerektirmez.
    ///
    /// `sudo -n -l <komut>` daha doğrudan görünüyor ama yanıltıcı: kullanıcı az
    /// önce terminalde sudo kullandıysa damga hâlâ geçerli olur ve kural hiç
    /// kurulmamışken de "izin var" cevabı döner. Beş dakika sonra da anahtar
    /// sebepsiz bozulmuş gibi görünürdü.
    static func isRuleInstalled() -> Bool {
        let manager = FileManager.default
        guard manager.isReadableFile(atPath: (sudoersPath as NSString).deletingLastPathComponent) else {
            // Dizin kapatılmışsa dolaylı yola düş; damga yanlış pozitifi burada
            // kabul ediliyor, alternatifi hiç cevap verememek.
            return Shell.run(sudoPath, ["-n", "-l", pmsetPath, "-a", "disablesleep", "1"]).ok
        }
        return manager.fileExists(atPath: sudoersPath)
    }

    static func setDisableSleep(_ disabled: Bool) throws {
        guard isRuleInstalled() else { throw Failure.notAuthorized }
        let result = Shell.run(sudoPath, ["-n", pmsetPath, "-a", "disablesleep", disabled ? "1" : "0"])
        guard result.ok else { throw Failure.failed(result.err) }
        // pmset 0 dönse bile ayarın gerçekten yerleştiğini görmek gerekiyor:
        // arayüz aksi halde açık görünürken kapak kapanınca Mac uyur.
        guard applied(disabled) else {
            throw Failure.failed("macOS did not apply the change. Try again, or check Energy settings.")
        }
    }

    /// IORegistry pmset'ten hemen sonra güncellenmeyebiliyor; kısa süre bekler.
    private static func applied(_ expected: Bool) -> Bool {
        for _ in 0..<5 {
            if (IORegistry.bool("SleepDisabled") ?? expected) == expected { return true }
            usleep(100_000)
        }
        return false
    }

    static func installRule() throws {
        // visudo doğrulaması atlanamaz: hatalı bir dosya /etc/sudoers.d içine
        // düşerse makinedeki tüm sudo kullanımı bozulur.
        let script = """
        set -e
        tmp="$(/usr/bin/mktemp /tmp/closenlid.XXXXXX)"
        /bin/cat > "$tmp" <<'CLOSENLID_RULE'
        \(ruleLine)
        CLOSENLID_RULE
        /bin/chmod 0440 "$tmp"
        /usr/sbin/visudo -c -f "$tmp" >/dev/null
        /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(sudoersPath)
        /bin/rm -f "$tmp"
        """
        try runAsAdmin(script,
                       prompt: "CloseNLid needs to install a one-time rule so it can block lid sleep without asking for your password each time.")
    }

    static func removeRule() throws {
        try runAsAdmin("/bin/rm -f \(sudoersPath)",
                       prompt: "CloseNLid needs to remove its administrator rule.")
    }

    private static func runAsAdmin(_ script: String, prompt: String) throws {
        let source = "do shell script \"\(Shell.appleScriptEscaped(script))\" "
            + "with prompt \"\(Shell.appleScriptEscaped(prompt))\" "
            + "with administrator privileges"
        let result = Shell.run("/usr/bin/osascript", ["-e", source], timeout: 120)
        guard result.ok else {
            if result.err.contains("-128") || result.err.lowercased().contains("cancel") {
                throw Failure.cancelled
            }
            throw Failure.failed(result.err)
        }
    }
}
