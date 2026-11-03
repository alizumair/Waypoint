import Foundation

/// Wire protocol constants and packet framing for Waypoint P2P communication.
public enum WaypointPacketType: UInt8, Codable, Sendable {
    case handshake            = 0x01
    case handshakeAck         = 0x02
    case ping                 = 0x03
    case pong                 = 0x04
    
    // File Transfer
    case fileManifest         = 0x10
    case fileChunk            = 0x11
    case fileTransferComplete = 0x12
    case fileTransferCancel   = 0x13
    
    // Continuity Ecosystem
    case clipboardSync        = 0x20
    case notificationRelay    = 0x30
    case mediaMetadataSync    = 0x40
    case mediaCommand         = 0x41
    
    // Screen Mirroring & Low-Latency Video
    case videoNALUnit         = 0x50
}

/// Binary header definition for all over-the-wire Waypoint packets.
/// Layout:
/// - 4 bytes: Magic ("WAYP")
/// - 1 byte: Protocol Version (0x01)
/// - 1 byte: WaypointPacketType
/// - 4 bytes: Big-Endian UInt32 Payload Length
public struct WaypointPacketHeader: Sendable {
    public static let magic: [UInt8] = [0x57, 0x41, 0x59, 0x50] // "WAYP"
    public static let currentVersion: UInt8 = 0x01
    public static let headerLength: Int = 10
    
    public let version: UInt8
    public let type: WaypointPacketType
    public let payloadLength: UInt32
    
    public init(type: WaypointPacketType, payloadLength: UInt32, version: UInt8 = currentVersion) {
        self.version = version
        self.type = type
        self.payloadLength = payloadLength
    }
    
    public func serialize() -> Data {
        var data = Data(WaypointPacketHeader.magic)
        data.append(version)
        data.append(type.rawValue)
        var lengthBigEndian = payloadLength.bigEndian
        withUnsafeBytes(of: &lengthBigEndian) { data.append(contentsOf: $0) }
        return data
    }
    
    public static func parse(from data: Data) -> WaypointPacketHeader? {
        guard data.count >= headerLength else { return nil }
        
        let magicBytes = Array(data[0..<4])
        guard magicBytes == magic else { return nil }
        
        let version = data[4]
        guard let packetType = WaypointPacketType(rawValue: data[5]) else { return nil }
        
        var rawLength: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &rawLength) { lengthBuf in
            data.copyBytes(to: lengthBuf, from: 6..<10)
        }
        let payloadLength = UInt32(bigEndian: rawLength)
        
        return WaypointPacketHeader(type: packetType, payloadLength: payloadLength, version: version)
    }
}

/// Helper wrapper for full packets containing a validated header and payload
public struct WaypointPacket: Sendable {
    public let header: WaypointPacketHeader
    public let payload: Data
    
    public init(type: WaypointPacketType, payload: Data) {
        self.header = WaypointPacketHeader(type: type, payloadLength: UInt32(payload.count))
        self.payload = payload
    }
    
    public func serialize() -> Data {
        var packetData = header.serialize()
        packetData.append(payload)
        return packetData
    }
}
