import AppKit
import Foundation

// Paketleme betiği ikonu buradan üretir: --make-icon <çıktı.png>
if let flagIndex = CommandLine.arguments.firstIndex(of: "--make-icon") {
    let output = CommandLine.arguments.count > flagIndex + 1
        ? CommandLine.arguments[flagIndex + 1]
        : "icon.png"
    guard let data = MainActor.assumeIsolated({ IconRenderer.renderPNG() }) else {
        print("Failed to render icon")
        exit(1)
    }
    do {
        try data.write(to: URL(fileURLWithPath: output))
        print("Wrote \(output)")
        exit(0)
    } catch {
        print("Failed to write \(output): \(error.localizedDescription)")
        exit(1)
    }
}

// Dock simgesi yok: bu bir durum çubuğu uygulaması. `.accessory` politikasında
// pencereler kendiliğinden öne gelmediği için ayarlar penceresi açılırken
// NSApp.activate elle çağrılıyor.
let application = NSApplication.shared
// Üst düzey kod ana iş parçacığında çalışıyor ama derleyici için nonisolated;
// AppDelegate @MainActor olduğundan kurulumu açıkça o bağlama alıyoruz.
let controller = MainActor.assumeIsolated { AppDelegate() }
application.delegate = controller
application.setActivationPolicy(.accessory)
application.run()
