import Foundation

/// Küçük ve senkron bir alt süreç çalıştırıcı.
///
/// Kabuk araya girmiyor: argümanlar doğrudan `execve`'ye gidiyor, dolayısıyla
/// tırnak ve kaçış sorunu oluşmuyor. Tek istisna `osascript`, orada kaçış
/// AppleScript metin sabiti için ayrıca yapılıyor.
enum Shell {

    struct Result {
        let status: Int32
        let out: String
        let err: String
        var ok: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) -> Result {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        // Şifre istemi beklemesin diye stdin kapalı: `sudo -n` zaten şifresiz
        // çalışamıyorsa hata dönmeli, asılı kalmamalı.
        task.standardInput = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return Result(status: -1, out: "", err: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline { usleep(20_000) }
        if task.isRunning { task.terminate() }
        task.waitUntilExit()

        return Result(status: task.terminationStatus, out: text(outData), err: text(errData))
    }

    private static func text(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// AppleScript metin sabitine gömülecek dizeyi kaçırır.
    static func appleScriptEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
             .replacingOccurrences(of: "\n", with: "\\n")
    }
}
