// KageriEditor フィーチャーグラフィック生成スクリプト（Google Play掲載用、1024x500）
// 実行: swift scripts/make_feature_graphic.swift
// 出力: ../KageriEditor-Android/store/feature_graphic.png
// デザイン: make_icon.swiftと同じノート+鉛筆アイコンを左に、アプリ名+キャッチコピーを右に配置
import AppKit

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
let subtitleColor = rgb(0x6B6860)

// ---- 112×112座標系（make_icon.swiftと同一デザイン、y下向き）でノート+鉛筆を描く ----
func drawIcon(_ c: CGContext) {
    c.addPath(CGPath(
        roundedRect: CGRect(x: 28, y: 22, width: 56, height: 68),
        cornerWidth: 7, cornerHeight: 7, transform: nil
    ))
    c.setStrokeColor(ink.cgColor)
    c.setLineWidth(5)
    c.strokePath()
    c.setFillColor(ink.cgColor)
    for y in [36.0, 56.0, 76.0] {
        c.fillEllipse(in: CGRect(x: 24, y: y - 4, width: 8, height: 8))
    }
    c.setFillColor(lineDark.cgColor)
    c.addPath(CGPath(roundedRect: CGRect(x: 42, y: 38, width: 30, height: 5),
                     cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
    c.fillPath()
    c.setFillColor(lineLight.cgColor)
    c.addPath(CGPath(roundedRect: CGRect(x: 42, y: 52, width: 24, height: 5),
                     cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
    c.fillPath()
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

/// 呼び出し側は自然なy-up（AppKit標準）座標系で(x,y)=左下・sizeで指定する。
/// ローカルにy-downへ反転してdrawIcon(112x112設計)を描く。
func drawIconAt(_ c: CGContext, x: CGFloat, y: CGFloat, size: CGFloat) {
    c.saveGState()
    c.translateBy(x: x, y: y + size)
    c.scaleBy(x: size / 112, y: -size / 112)
    drawIcon(c)
    c.restoreGState()
}

// ---- キャンバス ----
let width: CGFloat = 1024
let height: CGFloat = 500

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let c = gc.cgContext

// 背景（y-upの自然な座標のまま、フリップしない）
c.setFillColor(paper.cgColor)
c.fill(CGRect(x: 0, y: 0, width: width, height: height))

// アイコン（左側、縦中央）
let iconSize: CGFloat = 320
let iconX: CGFloat = 70
let iconY: CGFloat = (height - iconSize) / 2
drawIconAt(c, x: iconX, y: iconY, size: iconSize)

// タイトル + キャッチコピー（右側、縦中央）
let textX: CGFloat = iconX + iconSize + 50
let titleFont = NSFont.systemFont(ofSize: 72, weight: .bold)
let title = "KageriEditor"
let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: ink]
let titleSize = (title as NSString).size(withAttributes: titleAttrs)

let subtitleFont = NSFont.systemFont(ofSize: 30, weight: .medium)
let subtitle = "日本語の書き手のためのテキストエディタ"
let subtitleAttrs: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: subtitleColor]
let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)

let gap: CGFloat = 18
let blockHeight = titleSize.height + gap + subtitleSize.height
let blockTop = (height + blockHeight) / 2
let titleY = blockTop - titleSize.height
let subtitleY = titleY - gap - subtitleSize.height

(title as NSString).draw(at: NSPoint(x: textX, y: titleY), withAttributes: titleAttrs)
(subtitle as NSString).draw(at: NSPoint(x: textX, y: subtitleY), withAttributes: subtitleAttrs)

// アクセントの帯（アンバー、キャッチコピーの下）
c.setFillColor(amber.cgColor)
c.fill(CGRect(x: textX, y: subtitleY - 24, width: 64, height: 5))

gc.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let outDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("KageriEditor-Android/store")
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try! rep.representation(using: .png, properties: [:])!
    .write(to: outDir.appendingPathComponent("feature_graphic.png"))
print("Google Play: store/feature_graphic.png を生成")
