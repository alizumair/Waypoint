import AppKit
import CoreGraphics

func generateWaypointIcon() {
    let size: CGFloat = 1024
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Failed to create CGContext")
        return
    }
    
    // Draw macOS Squircle Base
    let inset: CGFloat = 80
    let squircleRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius: CGFloat = 190
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // Outer shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.setFillColor(CGColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1.0))
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Clip to squircle for inner contents
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    // Gradient Background
    let bgColors = [
        CGColor(red: 0.05, green: 0.07, blue: 0.15, alpha: 1.0),
        CGColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 1.0),
        CGColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.5, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 1024 - inset), end: CGPoint(x: 512, y: inset), options: [])
    }
    
    // Radiant Glow in Center
    let glowColors = [
        CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.35),
        CGColor(red: 0.38, green: 0.45, blue: 0.96, alpha: 0.15),
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.4, 1.0]) {
        ctx.drawRadialGradient(glowGradient, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 360, options: [])
    }
    
    // Radar / Concentric Rings
    ctx.setLineWidth(3.0)
    for radius in [120.0, 200.0, 280.0] as [CGFloat] {
        ctx.setStrokeColor(CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.35 - (radius / 1000.0)))
        ctx.strokeEllipse(in: CGRect(x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
    }
    
    // Navigational Crosshairs (Waypoint Theme)
    ctx.setStrokeColor(CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.25))
    ctx.setLineWidth(2.5)
    ctx.strokeLineSegments(between: [
        CGPoint(x: 512, y: 220), CGPoint(x: 512, y: 350),
        CGPoint(x: 512, y: 674), CGPoint(x: 512, y: 804),
        CGPoint(x: 220, y: 512), CGPoint(x: 350, y: 512),
        CGPoint(x: 674, y: 512), CGPoint(x: 804, y: 512)
    ])
    
    // Center Mac Silhouette / Waypoint Diamond Beacon
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 25, color: CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.9))
    
    // Outer Diamond
    let diamondPath = CGMutablePath()
    let dSize: CGFloat = 85
    diamondPath.move(to: CGPoint(x: 512, y: 512 + dSize * 1.3))
    diamondPath.addLine(to: CGPoint(x: 512 + dSize, y: 512))
    diamondPath.addLine(to: CGPoint(x: 512, y: 512 - dSize * 1.3))
    diamondPath.addLine(to: CGPoint(x: 512 - dSize, y: 512))
    diamondPath.closeSubpath()
    
    ctx.setFillColor(CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0))
    ctx.addPath(diamondPath)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Inner Core Apple / Diamond Cut
    ctx.saveGState()
    let innerCore = CGMutablePath()
    let innerSize: CGFloat = 40
    innerCore.move(to: CGPoint(x: 512, y: 512 + innerSize * 1.2))
    innerCore.addLine(to: CGPoint(x: 512 + innerSize, y: 512))
    innerCore.addLine(to: CGPoint(x: 512, y: 512 - innerSize * 1.2))
    innerCore.addLine(to: CGPoint(x: 512 - innerSize, y: 512))
    innerCore.closeSubpath()
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
    ctx.addPath(innerCore)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Orbital Connected Nodes (macOS, iOS, Android, PC)
    let nodePoints: [(CGPoint, String)] = [
        (CGPoint(x: 512, y: 740), "Top"),
        (CGPoint(x: 740, y: 512), "Right"),
        (CGPoint(x: 512, y: 284), "Bottom"),
        (CGPoint(x: 284, y: 512), "Left")
    ]
    
    for (pt, _) in nodePoints {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 15, color: CGColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 0.8))
        ctx.setFillColor(CGColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(x: pt.x - 14, y: pt.y - 14, width: 28, height: 28))
        ctx.restoreGState()
        
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
    }
    
    // Top Edge Highlight (Apple Glass Bevel)
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3))
    ctx.addPath(squirclePath)
    ctx.strokePath()
    
    ctx.restoreGState() // End squircle clip
    
    guard let cgImage = ctx.makeImage() else {
        print("Failed to make CGImage")
        return
    }
    
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Failed to get PNG representation")
        return
    }
    
    let outURL = URL(fileURLWithPath: "Assets/WaypointLogo.png")
    try? pngData.write(to: outURL)
    print("WaypointLogo.png successfully generated at \(outURL.path)")
}

generateWaypointIcon()
