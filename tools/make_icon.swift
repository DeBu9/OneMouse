import Cocoa
import CoreGraphics

// OneMouse 图标（精简版）：底板 + 鼠标剪影 + 滚轮槽 + 线性箭头
let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))
ctx.interpolationQuality = .high

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// ---- 底板 ----
let inset: CGFloat = 100
let board = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let boardPath = CGPath(roundedRect: board, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: rgb(0, 0, 0, 0.38))
ctx.addPath(boardPath)
ctx.setFillColor(rgb(16, 20, 26))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(boardPath)
ctx.clip()

let grad = CGGradient(colorsSpace: cs, colors: [
    rgb(60, 80, 106), rgb(29, 37, 49), rgb(14, 18, 24)
] as CFArray, locations: [0, 0.52, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: S / 2, y: board.maxY),
                       end: CGPoint(x: S / 2, y: board.minY), options: [])

let glow = CGGradient(colorsSpace: cs, colors: [
    rgb(122, 178, 255, 0.20), rgb(122, 178, 255, 0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: board.minX + 130, y: board.maxY - 70), startRadius: 0,
                       endCenter: CGPoint(x: board.minX + 130, y: board.maxY - 70), endRadius: 720,
                       options: [])
ctx.restoreGState()

// ---- 鼠标剪影 ----
let mw: CGFloat = 352
let mh: CGFloat = 438
let cx: CGFloat = S / 2
let cy: CGFloat = S / 2 + 58
let mouse = CGRect(x: cx - mw / 2, y: cy - mh / 2, width: mw, height: mh)
let mousePath = CGPath(roundedRect: mouse, cornerWidth: mw / 2, cornerHeight: mw / 2, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0, 0, 0, 0.48))
ctx.addPath(mousePath)
ctx.setFillColor(rgb(250, 251, 253))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(mousePath)
ctx.clip()
let mGrad = CGGradient(colorsSpace: cs, colors: [
    rgb(255, 255, 255), rgb(232, 237, 244), rgb(203, 213, 226)
] as CFArray, locations: [0, 0.62, 1])!
ctx.drawLinearGradient(mGrad,
                       start: CGPoint(x: cx, y: mouse.maxY),
                       end: CGPoint(x: cx, y: mouse.minY), options: [])

// 顶部一点点内阴影，避免纯白平板
let topShade = CGGradient(colorsSpace: cs, colors: [
    rgb(120, 140, 165, 0.18), rgb(120, 140, 165, 0)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(topShade,
                       start: CGPoint(x: cx, y: mouse.maxY),
                       end: CGPoint(x: cx, y: mouse.maxY - 90), options: [])
ctx.restoreGState()

// ---- 滚轮槽 ----
let wheelW: CGFloat = 56
let wheelH: CGFloat = 132
let wheelRect = CGRect(x: cx - wheelW / 2,
                       y: mouse.maxY - 128 - wheelH,
                       width: wheelW, height: wheelH)
let wheelPath = CGPath(roundedRect: wheelRect, cornerWidth: wheelW / 2, cornerHeight: wheelW / 2, transform: nil)

ctx.saveGState()
ctx.addPath(wheelPath)
ctx.setFillColor(rgb(22, 28, 37))
ctx.fillPath()
ctx.restoreGState()

// 滚轮内浅色横纹
ctx.saveGState()
ctx.addPath(wheelPath)
ctx.clip()
ctx.setStrokeColor(rgb(255, 255, 255, 0.26))
ctx.setLineWidth(6)
ctx.setLineCap(.round)
for dy in [-32, 0, 32] {
    ctx.move(to: CGPoint(x: cx - 13, y: wheelRect.midY + CGFloat(dy)))
    ctx.addLine(to: CGPoint(x: cx + 13, y: wheelRect.midY + CGFloat(dy)))
}
ctx.strokePath()
ctx.restoreGState()

// ---- 线性箭头 ----
let arrowY: CGFloat = board.minY + 176
let blue = rgb(64, 140, 255)
ctx.setShadow(offset: .zero, blur: 24, color: rgb(64, 140, 255, 0.55))
ctx.setStrokeColor(blue)
ctx.setFillColor(blue)
ctx.setLineWidth(16)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: cx - 122, y: arrowY))
ctx.addLine(to: CGPoint(x: cx + 74, y: arrowY))
ctx.strokePath()

ctx.move(to: CGPoint(x: cx + 128, y: arrowY))
ctx.addLine(to: CGPoint(x: cx + 70, y: arrowY + 36))
ctx.addLine(to: CGPoint(x: cx + 70, y: arrowY - 36))
ctx.closePath()
ctx.fillPath()

guard let image = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
