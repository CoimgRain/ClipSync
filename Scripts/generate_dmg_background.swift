#!/usr/bin/env swift

import AppKit

struct BackgroundSpec {
    let size = NSSize(width: 960, height: 560)
    let iconCenterY: CGFloat
    let leftIconCenterX: CGFloat
    let rightIconCenterX: CGFloat

    static let `default` = BackgroundSpec(
        iconCenterY: 324,
        leftIconCenterX: 248,
        rightIconCenterX: 700
    )
}

struct BackgroundLayoutConfig: Decodable {
    let iconCenterY: CGFloat?
    let leftIconCenterX: CGFloat?
    let rightIconCenterX: CGFloat?
}

func loadBackgroundSpec() -> BackgroundSpec {
    let configURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Scripts/dmg_background_layout.json")

    guard
        let data = try? Data(contentsOf: configURL),
        let config = try? JSONDecoder().decode(BackgroundLayoutConfig.self, from: data)
    else {
        return .default
    }

    return BackgroundSpec(
        iconCenterY: config.iconCenterY ?? BackgroundSpec.default.iconCenterY,
        leftIconCenterX: config.leftIconCenterX ?? BackgroundSpec.default.leftIconCenterX,
        rightIconCenterX: config.rightIconCenterX ?? BackgroundSpec.default.rightIconCenterX
    )
}

func savePNG(_ image: NSImage, to outputURL: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "ClipSyncDMG", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to convert DMG background to PNG."
        ])
    }

    try pngData.write(to: outputURL)
}

func drawCenteredText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .center
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    text.draw(in: rect, withAttributes: attributes)
}

func withShadow(color: NSColor, blur: CGFloat, x: CGFloat = 0, y: CGFloat = 0, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: x, height: y)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: generate_dmg_background.swift <output-path> [app-name]\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let appName = arguments.count >= 3 ? arguments[2] : "ClipSync"
let spec = loadBackgroundSpec()

let image = NSImage(size: spec.size)
image.lockFocus()

NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.15, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: spec.size)).fill()

let fullRect = NSRect(origin: .zero, size: spec.size)
NSGradient(colors: [
    NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.20, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.26, blue: 0.35, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.39, alpha: 1)
])?.draw(in: fullRect, angle: 325)

withShadow(color: NSColor(calibratedWhite: 0, alpha: 0.20), blur: 40, y: -10) {
    NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
    NSBezierPath(ovalIn: NSRect(x: 500, y: 380, width: 340, height: 220)).fill()
}

NSColor(calibratedRed: 0.38, green: 0.98, blue: 0.88, alpha: 0.16).setFill()
NSBezierPath(ovalIn: NSRect(x: 575, y: 330, width: 260, height: 170)).fill()

NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.26, alpha: 0.78).setFill()
let cardRect = NSRect(x: 26, y: 22, width: spec.size.width - 52, height: spec.size.height - 44)
NSBezierPath(roundedRect: cardRect, xRadius: 34, yRadius: 34).fill()

NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
let cardStroke = NSBezierPath(roundedRect: cardRect.insetBy(dx: 1.5, dy: 1.5), xRadius: 32, yRadius: 32)
cardStroke.lineWidth = 1.5
cardStroke.stroke()

let headerTextX: CGFloat = 90

drawCenteredText(
    "安装 \(appName)",
    in: NSRect(x: headerTextX, y: 432, width: 420, height: 44),
    font: .systemFont(ofSize: 30, weight: .bold),
    color: NSColor(calibratedWhite: 1, alpha: 0.96),
    alignment: .left
)

drawCenteredText(
    "将 \(appName) 拖入应用程序文件夹，即可完成安装",
    in: NSRect(x: headerTextX, y: 390, width: 760, height: 30),
    font: .systemFont(ofSize: 18, weight: .medium),
    color: NSColor(calibratedWhite: 1, alpha: 0.72),
    alignment: .left
)

let bandRect = NSRect(x: 90, y: 110, width: spec.size.width - 180, height: 230)
NSColor(calibratedWhite: 1, alpha: 0.05).setFill()
NSBezierPath(roundedRect: bandRect, xRadius: 28, yRadius: 28).fill()

let leftPlate = NSRect(x: spec.leftIconCenterX - 106, y: spec.iconCenterY - 96, width: 212, height: 188)
let rightPlate = NSRect(x: spec.rightIconCenterX - 106, y: spec.iconCenterY - 96, width: 212, height: 188)

for plate in [leftPlate, rightPlate] {
    withShadow(color: NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.12), blur: 14, y: -6) {
        NSColor(calibratedWhite: 1, alpha: 0.035).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 36, yRadius: 36).fill()
    }
    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    let stroke = NSBezierPath(roundedRect: plate.insetBy(dx: 1, dy: 1), xRadius: 35, yRadius: 35)
    stroke.lineWidth = 2
    stroke.setLineDash([10, 10], count: 2, phase: 0)
    stroke.stroke()
}

let arrowStart = NSPoint(x: spec.leftIconCenterX + 126, y: spec.iconCenterY + 2)
let arrowEnd = NSPoint(x: spec.rightIconCenterX - 126, y: spec.iconCenterY + 2)
let arrowPath = NSBezierPath()
arrowPath.move(to: arrowStart)
arrowPath.line(to: arrowEnd)
arrowPath.lineWidth = 14
arrowPath.lineCapStyle = .round

withShadow(color: NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.12, alpha: 0.32), blur: 20, y: -6) {
    NSColor(calibratedRed: 0.58, green: 0.98, blue: 0.90, alpha: 0.72).setStroke()
    arrowPath.stroke()
}

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: arrowEnd.x - 20, y: arrowEnd.y + 24))
arrowHead.line(to: NSPoint(x: arrowEnd.x + 18, y: arrowEnd.y))
arrowHead.line(to: NSPoint(x: arrowEnd.x - 20, y: arrowEnd.y - 24))
arrowHead.lineJoinStyle = .round
arrowHead.lineCapStyle = .round
arrowHead.lineWidth = 13
NSColor(calibratedRed: 0.63, green: 1.0, blue: 0.92, alpha: 0.80).setStroke()
arrowHead.stroke()

drawCenteredText(
    "如果首次打开被系统拦截，请右键应用并选择“打开”",
    in: NSRect(x: 70, y: 54, width: spec.size.width - 140, height: 22),
    font: .systemFont(ofSize: 14, weight: .medium),
    color: NSColor(calibratedWhite: 1, alpha: 0.48)
)

image.unlockFocus()

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try savePNG(image, to: outputURL)
