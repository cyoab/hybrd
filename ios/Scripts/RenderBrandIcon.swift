// Reproducible vector rendering of hybrd's h + Terra dot app mark.
// Usage: swift RenderBrandIcon.swift /absolute/path/Icon.png
import AppKit
import ImageIO

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard CommandLine.arguments.count == 2,
      let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
  fatalError("Provide a destination PNG path.")
}
context.setFillColor(red: 13.0 / 255, green: 13.0 / 255, blue: 14.0 / 255, alpha: 1)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
context.setLineWidth(64)
context.setLineCap(.butt)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 298, y: 245))
context.addLine(to: CGPoint(x: 298, y: 777))
context.move(to: CGPoint(x: 298, y: 450))
context.addCurve(to: CGPoint(x: 617, y: 450),
  control1: CGPoint(x: 298, y: 665), control2: CGPoint(x: 617, y: 665))
context.addLine(to: CGPoint(x: 617, y: 391))
context.strokePath()
context.setFillColor(red: 1, green: 107.0 / 255, blue: 61.0 / 255, alpha: 1)
context.fillEllipse(in: CGRect(x: 649, y: 242, width: 154, height: 154))
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
        "public.png" as CFString, 1, nil) else { fatalError("Could not create icon.") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon.") }
print("Rendered opaque 1024 × 1024 hybrd mark")
