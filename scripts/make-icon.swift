import AppKit

// วาดไอคอนแอป: พื้นไล่สีน้ำเงิน-ม่วง + แท่งคลื่นเสียงสีขาว
// ใช้: swift scripts/make-icon.swift <output.png>

let sizePx = 1024.0
let image = NSImage(size: NSSize(width: sizePx, height: sizePx))
image.lockFocus()

let inset = sizePx * 0.09
let rect = NSRect(x: inset, y: inset, width: sizePx - inset * 2, height: sizePx - inset * 2)
let radius = rect.width * 0.225
let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.35, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.55, green: 0.20, blue: 0.95, alpha: 1),
])!.draw(in: background, angle: -65)

NSColor.white.setFill()
let heights: [Double] = [0.18, 0.34, 0.52, 0.72, 0.52, 0.34, 0.18]
let barWidth = rect.width * 0.055
let gap = rect.width * 0.045
let totalWidth = Double(heights.count) * barWidth + Double(heights.count - 1) * gap
var x = rect.midX - totalWidth / 2
for height in heights {
    let barHeight = rect.height * height
    let barRect = NSRect(x: x, y: rect.midY - barHeight / 2, width: barWidth, height: barHeight)
    NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1]) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
