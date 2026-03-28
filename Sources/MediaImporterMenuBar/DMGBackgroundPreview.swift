import AppKit
import SwiftUI

private struct DMGBackgroundPreviewLayout: Decodable, Equatable {
    let iconCenterY: CGFloat
    let leftIconCenterX: CGFloat
    let rightIconCenterX: CGFloat
    let appIconPositionX: CGFloat
    let appIconPositionY: CGFloat
    let applicationsIconPositionX: CGFloat
    let applicationsIconPositionY: CGFloat

    static let `default` = DMGBackgroundPreviewLayout(
        iconCenterY: 324,
        leftIconCenterX: 248,
        rightIconCenterX: 700,
        appIconPositionX: 248,
        appIconPositionY: 300,
        applicationsIconPositionX: 700,
        applicationsIconPositionY: 300
    )
}

private enum DMGBackgroundPreviewLoader {
    static let rootURL: URL = {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    static let configURL = rootURL.appendingPathComponent("Scripts/dmg_background_layout.json")
    static let appIconURL = rootURL.appendingPathComponent("App/AppIcon-1024.png")

    static func loadLayout() -> DMGBackgroundPreviewLayout {
        guard
            let data = try? Data(contentsOf: configURL),
            let layout = try? JSONDecoder().decode(DMGBackgroundPreviewLayout.self, from: data)
        else {
            return .default
        }

        return layout
    }
}

private struct DMGBackgroundPreviewView: View {
    @State private var layout = DMGBackgroundPreviewLoader.loadLayout()
    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(nsImage: makePreviewImage())
                .interpolation(.high)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 960, height: 560)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            Text("编辑 Scripts/dmg_background_layout.json 后，这个预览会自动刷新")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Text(DMGBackgroundPreviewLoader.configURL.path)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .textSelection(.enabled)
        }
        .padding(24)
        .background(Color.black.opacity(0.88))
        .onReceive(timer) { _ in
            let updated = DMGBackgroundPreviewLoader.loadLayout()
            if updated != layout {
                layout = updated
            }
        }
    }

    private func makePreviewImage() -> NSImage {
        let size = NSSize(width: 960, height: 560)
        let image = NSImage(size: size)

        image.lockFocus()

        let fullRect = NSRect(origin: .zero, size: size)
        NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(rect: fullRect).fill()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.07, green: 0.26, blue: 0.35, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.39, alpha: 1),
        ])?.draw(in: fullRect, angle: 325)

        DMGBackgroundPreviewDrawing.withShadow(
            color: NSColor(calibratedWhite: 0, alpha: 0.20),
            blur: 40,
            y: -10
        ) {
            NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
            NSBezierPath(ovalIn: NSRect(x: 500, y: 380, width: 340, height: 220)).fill()
        }

        NSColor(calibratedRed: 0.38, green: 0.98, blue: 0.88, alpha: 0.16).setFill()
        NSBezierPath(ovalIn: NSRect(x: 575, y: 330, width: 260, height: 170)).fill()

        let cardRect = NSRect(x: 26, y: 22, width: size.width - 52, height: size.height - 44)
        NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.26, alpha: 0.78).setFill()
        NSBezierPath(roundedRect: cardRect, xRadius: 34, yRadius: 34).fill()

        NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
        let cardStroke = NSBezierPath(
            roundedRect: cardRect.insetBy(dx: 1.5, dy: 1.5),
            xRadius: 32,
            yRadius: 32
        )
        cardStroke.lineWidth = 1.5
        cardStroke.stroke()

        let headerTextX: CGFloat = 90

        DMGBackgroundPreviewDrawing.drawText(
            "安装 ClipSync",
            in: NSRect(x: headerTextX, y: 432, width: 420, height: 44),
            font: .systemFont(ofSize: 30, weight: .bold),
            color: NSColor(calibratedWhite: 1, alpha: 0.96),
            alignment: .left
        )

        DMGBackgroundPreviewDrawing.drawText(
            "将 ClipSync 拖入应用程序文件夹，即可完成安装",
            in: NSRect(x: headerTextX, y: 390, width: 760, height: 30),
            font: .systemFont(ofSize: 18, weight: .medium),
            color: NSColor(calibratedWhite: 1, alpha: 0.72),
            alignment: .left
        )

        let bandRect = NSRect(x: 90, y: 110, width: size.width - 180, height: 230)
        NSColor(calibratedWhite: 1, alpha: 0.05).setFill()
        NSBezierPath(roundedRect: bandRect, xRadius: 28, yRadius: 28).fill()

        let leftPlate = NSRect(
            x: layout.leftIconCenterX - 106,
            y: layout.iconCenterY - 96,
            width: 212,
            height: 188
        )
        let rightPlate = NSRect(
            x: layout.rightIconCenterX - 106,
            y: layout.iconCenterY - 96,
            width: 212,
            height: 188
        )

        for plate in [leftPlate, rightPlate] {
            DMGBackgroundPreviewDrawing.withShadow(
                color: NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.12),
                blur: 14,
                y: -6
            ) {
                NSColor(calibratedWhite: 1, alpha: 0.035).setFill()
                NSBezierPath(roundedRect: plate, xRadius: 36, yRadius: 36).fill()
            }
            NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
            let stroke = NSBezierPath(roundedRect: plate.insetBy(dx: 1, dy: 1), xRadius: 35, yRadius: 35)
            stroke.lineWidth = 2
            stroke.setLineDash([10, 10], count: 2, phase: 0)
            stroke.stroke()
        }

        let arrowStart = NSPoint(x: layout.leftIconCenterX + 126, y: layout.iconCenterY + 2)
        let arrowEnd = NSPoint(x: layout.rightIconCenterX - 126, y: layout.iconCenterY + 2)
        let arrowPath = NSBezierPath()
        arrowPath.move(to: arrowStart)
        arrowPath.line(to: arrowEnd)
        arrowPath.lineWidth = 14
        arrowPath.lineCapStyle = .round

        DMGBackgroundPreviewDrawing.withShadow(
            color: NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.12, alpha: 0.32),
            blur: 20,
            y: -6
        ) {
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

        if let appIcon = NSImage(contentsOf: DMGBackgroundPreviewLoader.appIconURL) {
            let appIconRect = NSRect(
                x: layout.appIconPositionX - 78,
                y: layout.appIconPositionY - 42,
                width: 118,
                height: 118
            )
            appIcon.draw(in: appIconRect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        let applicationsIcon = NSWorkspace.shared.icon(forFile: "/Applications")
        let applicationsRect = NSRect(
            x: layout.applicationsIconPositionX - 80,
            y: layout.applicationsIconPositionY - 40,
            width: 128,
            height: 112
        )
        applicationsIcon.draw(in: applicationsRect, from: .zero, operation: .sourceOver, fraction: 1)

        DMGBackgroundPreviewDrawing.drawText(
            "如果首次打开被系统拦截，请右键应用并选择“打开”",
            in: NSRect(x: 70, y: 54, width: size.width - 140, height: 22),
            font: .systemFont(ofSize: 14, weight: .medium),
            color: NSColor(calibratedWhite: 1, alpha: 0.48)
        )

        image.unlockFocus()
        return image
    }
}

private enum DMGBackgroundPreviewDrawing {
    static func drawText(
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
            .paragraphStyle: paragraph,
        ]

        text.draw(in: rect, withAttributes: attributes)
    }

    static func withShadow(color: NSColor, blur: CGFloat, x: CGFloat = 0, y: CGFloat = 0, draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: x, height: y)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct DMGBackgroundPreview_Previews: PreviewProvider {
    static var previews: some View {
        DMGBackgroundPreviewView()
            .preferredColorScheme(.dark)
    }
}
