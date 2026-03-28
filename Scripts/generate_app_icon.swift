import AppKit

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appDirectory = projectRoot.appendingPathComponent("App", isDirectory: true)
let iconsetDirectory = appDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let basePNGURL = appDirectory.appendingPathComponent("AppIcon-1024.png")

let sourceCandidates = [
    appDirectory.appendingPathComponent("AppIcon-Source.png"),
    appDirectory.appendingPathComponent("AppIcon-Source.jpg"),
    appDirectory.appendingPathComponent("AppIcon-Source.jpeg"),
]

guard let sourceURL = sourceCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
    fputs("Missing source image. Put your logo at App/AppIcon-Source.png or App/AppIcon-Source.jpg\n", stderr)
    exit(1)
}

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Failed to load source image at \(sourceURL.path)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: iconsetDirectory)
try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

func rasterize(_ image: NSImage, size: CGFloat) -> NSImage {
    let output = NSImage(size: NSSize(width: size, height: size))
    output.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    output.unlockFocus()
    return output
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

let image = rasterize(sourceImage, size: 1024)
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
    try savePNG(rasterize(sourceImage, size: size), to: iconsetDirectory.appendingPathComponent(name))
}

print("Generated icon from \(sourceURL.lastPathComponent)")
