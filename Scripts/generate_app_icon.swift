import AppKit

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appDirectory = projectRoot.appendingPathComponent("App", isDirectory: true)
let iconsetDirectory = appDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let basePNGURL = appDirectory.appendingPathComponent("AppIcon-1024.png")

try? FileManager.default.removeItem(at: iconsetDirectory)
try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

func drawSymbol(
    _ name: String,
    pointSize: CGFloat,
    color: NSColor,
    rect: NSRect,
    weight: NSFont.Weight = .regular
) {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        return
    }

    let sizeConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: color)
    let config = sizeConfig.applying(colorConfig)
    let configured = symbol.withSymbolConfiguration(config) ?? symbol
    configured.draw(in: rect)
}

func makeBaseIcon() -> NSImage {
    let canvasSize = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: canvasSize)
    image.lockFocus()

    let canvasRect = NSRect(origin: .zero, size: canvasSize)
    let tileRect = canvasRect.insetBy(dx: 42, dy: 42)

    let background = NSBezierPath(roundedRect: tileRect, xRadius: 220, yRadius: 220)
    NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 1).setFill()
    background.fill()

    if let gradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.12),
        NSColor(calibratedWhite: 1, alpha: 0.02),
    ]) {
        gradient.draw(in: background, relativeCenterPosition: NSPoint(x: -0.55, y: 1.15))
    }

    let outlineRect = tileRect.insetBy(dx: 18, dy: 18)
    let outline = NSBezierPath(roundedRect: outlineRect, xRadius: 200, yRadius: 200)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    outline.lineWidth = 5
    outline.stroke()

    let folderRect = NSRect(x: 176, y: 224, width: 672, height: 552)
    drawSymbol(
        "folder.fill",
        pointSize: 656,
        color: NSColor(calibratedRed: 0.37, green: 0.82, blue: 0.60, alpha: 1),
        rect: folderRect,
        weight: .regular
    )

    let mediaRect = NSRect(x: 378, y: 388, width: 268, height: 226)
    drawSymbol(
        "photo.stack.fill",
        pointSize: 258,
        color: NSColor.white.withAlphaComponent(0.95),
        rect: mediaRect,
        weight: .regular
    )

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }

    try png.write(to: url)
}

let image = makeBaseIcon()
try savePNG(image, to: basePNGURL)

let iconSizes: [String: CGFloat] = [
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
]

for (name, size) in iconSizes {
    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    resized.unlockFocus()
    try savePNG(resized, to: iconsetDirectory.appendingPathComponent(name))
}

print("Generated icon at \(basePNGURL.path)")
