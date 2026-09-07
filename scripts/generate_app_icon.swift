import AppKit

let output = "Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
let directory = URL(fileURLWithPath: output).deletingLastPathComponent()
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSColor(calibratedRed: 0.012, green: 0.055, blue: 0.065, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let white = NSColor(calibratedWhite: 0.97, alpha: 1)
let green = NSColor(calibratedRed: 0.04, green: 0.92, blue: 0.48, alpha: 1)
let attrs90: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 360, weight: .black),
    .foregroundColor: white,
    .paragraphStyle: paragraph
]
let attrsPlus: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 300, weight: .black),
    .foregroundColor: green,
    .paragraphStyle: paragraph
]
NSString(string: "90").draw(in: NSRect(x: 105, y: 315, width: 590, height: 410), withAttributes: attrs90)
NSString(string: "+").draw(in: NSRect(x: 605, y: 350, width: 300, height: 340), withAttributes: attrsPlus)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Unable to create app icon")
}
try png.write(to: URL(fileURLWithPath: output))
print("Generated \(output) (\(png.count) bytes)")
