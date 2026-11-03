import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

public enum QRGenerator {
    private static let context = CIContext()
    
    /// Generates a sharp NSImage of a QR Code for the given string content.
    public static func generateQRCode(from string: String, targetSize: CGSize = CGSize(width: 280, height: 280)) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel") // Medium correction level for good density
        
        guard let outputCIImage = filter.outputImage else { return nil }
        
        // Scale the image cleanly without anti-aliasing blur
        let scaleX = targetSize.width / outputCIImage.extent.size.width
        let scaleY = targetSize.height / outputCIImage.extent.size.height
        let transformedImage = outputCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: targetSize)
    }
}
