// KageriEditor 共通アイコン生成スクリプト（Mac + Android）
// 実行: swift scripts/make_icon.swift
// 出力: Resources/AppIcon.icns（Mac）、../KageriEditor-Android/app/src/main/res/mipmap-*（Android）、
//       ../KageriEditor-Android/store/play_store_512.png（Google Play）
// デザイン: 白地にリングノートの線画＋琥珀色の鉛筆（2026-07 確定版）
import AppKit

// ---- 配色 ----
func rgb(_ hex: Int) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
        green: CGFloat((hex >> 8) & 0xFF) / 255.0,
        blue: CGFloat(hex & 0xFF) / 255.0,
        alpha: 1
    )
}
let paper = rgb(0xFCFAF5)
let ink = rgb(0x232B36)
let lineDark = rgb(0x9E9B93)
let lineLight = rgb(0xD4D1C9)
let amber = rgb(0xEF9F27)
let coral = rgb(0xD85A30)
let wood = rgb(0xE8CFA4)
let graphite = rgb(0x3A3A38)

// ---- 112×112 座標系（SVG案と同一・y下向き）で中身を描く ----
func drawContent(_ c: CGContext) {
    // ノート枠（キャンバス中央(x=56)に水平中心が来るよう、旧デザインから+4シフト）
    c.addPath(CGPath(
        roundedRect: CGRect(x: 28, y: 22, width: 56, height: 68),
        cornerWidth: 7, cornerHeight: 7, transform: nil
    ))
    c.setStrokeColor(ink.cgColor)
    c.setLineWidth(5)
    c.strokePath()
    // リング
    c.setFillColor(ink.cgColor)
    for y in [36.0, 56.0, 76.0] {
        c.fillEllipse(in: CGRect(x: 24, y: y - 4, width: 8, height: 8))
    }
    // 本文の線
    c.setFillColor(lineDark.cgColor)
    c.addPath(CGPath(roundedRect: CGRect(x: 42, y: 38, width: 30, height: 5),
                     cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
    c.fillPath()
    c.setFillColor(lineLight.cgColor)
    c.addPath(CGPath(roundedRect: CGRect(x: 42, y: 52, width: 24, height: 5),
                     cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
    c.fillPath()
    // 鉛筆（45度）。ノート右下角との相対位置を保つため回転の中心もノートと
    // 同じ+4シフト（(76,72)→(80,72)）。ただしそのままでは回転後の右端が
    // x≈112.5とキャンバス外にはみ出すため、0.8倍に縮小して余裕を持たせる
    // （旧デザインでもシフト前で右端x≈108.5とほぼ限界だった）。
    c.saveGState()
    c.translateBy(x: 80, y: 72)
    c.rotate(by: 45 * .pi / 180)
    c.scaleBy(x: 0.8, y: 0.8)
    c.translateBy(x: -76, y: -72)
    c.setFillColor(amber.cgColor)
    c.addPath(CGPath(roundedRect: CGRect(x: 69, y: 33, width: 14, height: 44),
                     cornerWidth: 2, cornerHeight: 2, transform: nil))
    c.fillPath()
    c.setFillColor(coral.cgColor)
    c.addPath(CGPath(roundedRect: CGRect(x: 69, y: 33, width: 14, height: 8),
                     cornerWidth: 2, cornerHeight: 2, transform: nil))
    c.fillPath()
    c.setFillColor(wood.cgColor)
    c.beginPath()
    c.move(to: CGPoint(x: 69, y: 77))
    c.addLine(to: CGPoint(x: 83, y: 77))
    c.addLine(to: CGPoint(x: 76, y: 90.5))
    c.closePath()
    c.fillPath()
    c.setFillColor(graphite.cgColor)
    c.beginPath()
    c.move(to: CGPoint(x: 73.4, y: 85.4))
    c.addLine(to: CGPoint(x: 78.6, y: 85.4))
    c.addLine(to: CGPoint(x: 76, y: 90.5))
    c.closePath()
    c.fillPath()
    c.restoreGState()
}

enum IconStyle {
    case macSquircle     // Big Sur流: 余白つき白プレート＋影
    case androidRounded  // 全面角丸（従来型ランチャー用）
    case square          // 全面正方形（Google Play掲載用）
}

func renderPNG(pixels: Int, style: IconStyle) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = NSGraphicsContext.current!.cgContext
    let px = CGFloat(pixels)

    // y下向きの座標系にする（SVGと同じ向き）
    c.translateBy(x: 0, y: px)
    c.scaleBy(x: 1, y: -1)

    switch style {
    case .macSquircle:
        let margin = px * 100 / 1024
        let radius = px * 185 / 1024
        let plate = CGRect(x: margin, y: margin, width: px - margin * 2, height: px - margin * 2)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -px * 12 / 1024),
                    blur: px * 26 / 1024,
                    color: NSColor.black.withAlphaComponent(0.35).cgColor)
        c.setFillColor(paper.cgColor)
        c.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
        c.fillPath()
        c.restoreGState()
        let scale = px * 0.66 / 112
        c.translateBy(x: (px - 112 * scale) / 2, y: (px - 112 * scale) / 2)
        c.scaleBy(x: scale, y: scale)
        drawContent(c)
    case .androidRounded:
        let radius = px * 25 / 112
        c.setFillColor(paper.cgColor)
        c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: px, height: px),
                         cornerWidth: radius, cornerHeight: radius, transform: nil))
        c.fillPath()
        c.scaleBy(x: px / 112, y: px / 112)
        drawContent(c)
    case .square:
        c.setFillColor(paper.cgColor)
        c.fill(CGRect(x: 0, y: 0, width: px, height: px))
        c.scaleBy(x: px / 112, y: px / 112)
        drawContent(c)
    }

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// ---- 出力 ----
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
let resourcesDir = scriptDir.appendingPathComponent("Resources")
let androidRes = scriptDir.deletingLastPathComponent()
    .appendingPathComponent("KageriEditor-Android/app/src/main/res")
let androidStore = scriptDir.deletingLastPathComponent()
    .appendingPathComponent("KageriEditor-Android/store")
let fm = FileManager.default

// Mac iconset → icns
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconsetDir)
try! fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
let macVariants: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (px, name) in macVariants {
    try! renderPNG(pixels: px, style: .macSquircle)
        .write(to: iconsetDir.appendingPathComponent("\(name).png"))
}
try! renderPNG(pixels: 256, style: .macSquircle)
    .write(to: resourcesDir.appendingPathComponent("AppIconPreview.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path,
                      "-o", resourcesDir.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
try? fm.removeItem(at: iconsetDir)
print("Mac: Resources/AppIcon.icns を生成")

// Android mipmap PNG
let androidVariants: [(Int, String)] = [
    (48, "mdpi"), (72, "hdpi"), (96, "xhdpi"), (144, "xxhdpi"), (192, "xxxhdpi"),
]
for (px, density) in androidVariants {
    let dir = androidRes.appendingPathComponent("mipmap-\(density)")
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try! renderPNG(pixels: px, style: .androidRounded)
        .write(to: dir.appendingPathComponent("ic_launcher.png"))
}
print("Android: mipmap PNG を生成")

// Google Play 掲載用 512px（全面正方形）
try! fm.createDirectory(at: androidStore, withIntermediateDirectories: true)
try! renderPNG(pixels: 512, style: .square)
    .write(to: androidStore.appendingPathComponent("play_store_512.png"))
print("Google Play: store/play_store_512.png を生成")
