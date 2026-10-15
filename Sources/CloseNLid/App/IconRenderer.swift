import AppKit

/// Paketleme betiği ikonu buradan üretir: `CloseNLid --make-icon <çıktı.png>`.
///
/// Ayrı bir tasarım dosyası tutmamanın sebebi: ikon bir arka plan ve tek bir
/// sistem simgesinden ibaret. Koddan üretmek onu menü çubuğundaki simgeyle
/// aynı kaynaktan besliyor, ikisi ayrı ayrı eskimiyor.
@MainActor
enum IconRenderer {

    static func renderPNG(size: CGFloat = 1024) -> Data? {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            // macOS ikon ızgarası kenarlarda boşluk bırakıyor; kare tam kenara
            // dayanırsa Dock'ta diğer ikonlardan büyük görünüyor.
            let inset = size * 0.09
            let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
            let radius = rect.width * 0.225
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
            let colors = [
                NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.98, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.05, green: 0.16, blue: 0.48, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(gradient,
                                           start: CGPoint(x: rect.minX, y: rect.maxY),
                                           end: CGPoint(x: rect.maxX, y: rect.minY),
                                           options: [])
            }
            context.restoreGState()
        }

        drawSymbol(in: image.size, size: size)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// SF Symbol'ü beyaza boyayıp ortalar. Simgeler şablon olduğu için renk
    /// doğrudan verilemiyor; maske olarak kullanılıyor.
    private static func drawSymbol(in canvas: NSSize, size: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }

        let white = NSImage(size: symbol.size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        let target = NSRect(x: (canvas.width - white.size.width) / 2,
                            y: (canvas.height - white.size.height) / 2,
                            width: white.size.width,
                            height: white.size.height)
        white.draw(in: target)
    }
}
