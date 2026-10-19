import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 205, yRadius: 205)
NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.20, blue: 0.27, alpha: 1), ending: NSColor(calibratedRed: 0.06, green: 0.46, blue: 0.38, alpha: 1))!.draw(in: background, angle: 70)
NSColor(calibratedWhite: 0.91, alpha: 1).setStroke()
let screen = NSBezierPath(roundedRect: NSRect(x: 224, y: 367, width: 576, height: 370), xRadius: 33, yRadius: 33)
screen.lineWidth = 28
screen.stroke()
let base = NSBezierPath()
base.move(to: NSPoint(x: 171, y: 319))
base.line(to: NSPoint(x: 853, y: 319))
base.lineWidth = 28
base.lineCapStyle = .round
base.stroke()
NSColor(calibratedRed: 0.27, green: 0.91, blue: 0.65, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 336, y: 456, width: 352, height: 177), xRadius: 89, yRadius: 89).fill()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 526, y: 473, width: 143, height: 143)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
