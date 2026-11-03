import Foundation
import AVFoundation
import VideoToolbox
import AppKit

/// Low-latency H.264 NAL unit decoder and video renderer for screen mirroring.
/// Ingests elementary H.264 stream chunks (SPS, PPS, IDR, non-IDR) from Android MediaCodec
/// and renders directly via AVSampleBufferDisplayLayer with zero copying.
@MainActor
public final class VideoStreamingPipeline: NSObject, ObservableObject {
    public static let shared = VideoStreamingPipeline()
    
    @Published public private(set) var isStreamActive: Bool = false
    @Published public private(set) var currentResolution: CGSize = .zero
    @Published public private(set) var frameCount: UInt64 = 0
    
    // Core Video / AVFoundation display layer
    public let displayLayer = AVSampleBufferDisplayLayer()
    
    private var formatDescription: CMVideoFormatDescription?
    private var spsData: Data?
    private var ppsData: Data?
    
    public override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.isOpaque = true
        
        // Wire up incoming NAL unit callback from P2PNetworkManager
        P2PNetworkManager.shared.onVideoFrameReceived = { [weak self] nalu in
            Task { @MainActor in
                self?.handleIncomingNALU(nalu)
            }
        }
    }
    
    // MARK: - Inbound NAL Unit Processing
    
    public func handleIncomingNALU(_ payload: VideoNALUPayload) {
        let nalBytes = payload.nalData
        guard !nalBytes.isEmpty else { return }
        
        switch payload.nalType {
        case .sps:
            self.spsData = nalBytes
            tryBuildFormatDescription()
            
        case .pps:
            self.ppsData = nalBytes
            tryBuildFormatDescription()
            
        case .idr, .nonIDR:
            guard let format = formatDescription else { return }
            renderFrame(nalData: nalBytes, format: format, timestampUs: payload.timestampUs)
            
        default:
            break
        }
    }
    
    // MARK: - Format Description (SPS + PPS)
    
    private func tryBuildFormatDescription() {
        guard let sps = spsData, let pps = ppsData else { return }
        
        sps.withUnsafeBytes { spsBuffer in
            pps.withUnsafeBytes { ppsBuffer in
                guard let spsBase = spsBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBase = ppsBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                
                var formatDesc: CMFormatDescription?
                let parameterSetPointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                let parameterSetSizes: [Int] = [sps.count, pps.count]
                
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDesc
                )
                
                if status == noErr, let format = formatDesc {
                    self.formatDescription = format
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                    self.currentResolution = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
                    self.isStreamActive = true
                    print("[Waypoint Mirroring] Format description ready: \(dimensions.width)x\(dimensions.height)")
                } else {
                    print("[Waypoint Mirroring] Failed to create format description: \(status)")
                }
            }
        }
    }
    
    // MARK: - CMSampleBuffer Construction & Render
    
    private func renderFrame(nalData: Data, format: CMVideoFormatDescription, timestampUs: UInt64) {
        // Construct AVCC format (4-byte length prefix + NAL data)
        var avccData = Data()
        var lengthBigEndian = UInt32(nalData.count).bigEndian
        withUnsafeBytes(of: &lengthBigEndian) { avccData.append(contentsOf: $0) }
        avccData.append(nalData)
        
        var blockBuffer: CMBlockBuffer?
        let memoryBlock = UnsafeMutableRawPointer.allocate(byteCount: avccData.count, alignment: 1)
        avccData.copyBytes(to: memoryBlock.assumingMemoryBound(to: UInt8.self), count: avccData.count)
        
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: memoryBlock,
            blockLength: avccData.count,
            blockAllocator: kCFAllocatorMalloc,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard blockStatus == noErr, let buffer = blockBuffer else {
            memoryBlock.deallocate()
            return
        }
        
        // Calculate presentation timestamp (PTS)
        let pts = CMTime(value: CMTimeValue(timestampUs), timescale: 1_000_000)
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: CMTime.invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        var sampleSizeArray = [avccData.count]
        
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )
        
        guard sampleStatus == noErr, let finalSampleBuffer = sampleBuffer else {
            return
        }
        
        // Enqueue directly to AVSampleBufferDisplayLayer
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        
        displayLayer.enqueue(finalSampleBuffer)
        frameCount += 1
    }
    
    public func resetStream() {
        displayLayer.flush()
        formatDescription = nil
        spsData = nil
        ppsData = nil
        isStreamActive = false
        frameCount = 0
    }
}
