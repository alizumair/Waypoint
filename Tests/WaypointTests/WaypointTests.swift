import Testing
import Foundation
@testable import Waypoint

@Suite("Waypoint Core Protocol Tests")
struct WaypointTests {
    
    @Test("Packet Header Serialization and Deserialization")
    func testHeaderSerialization() {
        let originalHeader = WaypointPacketHeader(type: .fileManifest, payloadLength: 1024, version: 1)
        let serialized = originalHeader.serialize()
        
        #expect(serialized.count == WaypointPacketHeader.headerLength)
        
        let parsed = WaypointPacketHeader.parse(from: serialized)
        #expect(parsed != nil)
        #expect(parsed?.type == .fileManifest)
        #expect(parsed?.payloadLength == 1024)
        #expect(parsed?.version == 1)
    }
    
    @Test("Full Packet Roundtrip")
    func testPacketRoundtrip() {
        let dummyPayload = "Hello Waypoint Local Bridge".data(using: .utf8)!
        let packet = WaypointPacket(type: .clipboardSync, payload: dummyPayload)
        let packetData = packet.serialize()
        
        #expect(packetData.count == WaypointPacketHeader.headerLength + dummyPayload.count)
        
        let parsedHeader = WaypointPacketHeader.parse(from: packetData)
        #expect(parsedHeader != nil)
        #expect(parsedHeader?.type == .clipboardSync)
        #expect(parsedHeader?.payloadLength == UInt32(dummyPayload.count))
    }
    
    @Test("Device Handshake Model Encoding")
    func testDeviceHandshake() throws {
        let handshake = DeviceHandshake(
            deviceId: "test-device-uuid",
            deviceName: "Zumi MacBook",
            platform: .macOS,
            model: "MacBookPro",
            appVersion: "1.0.0",
            supportedFeatures: ["file_transfer", "clipboard_sync"],
            localPort: 53890
        )
        
        let encoded = try JSONEncoder().encode(handshake)
        let decoded = try JSONDecoder().decode(DeviceHandshake.self, from: encoded)
        
        #expect(decoded.deviceId == "test-device-uuid")
        #expect(decoded.deviceName == "Zumi MacBook")
        #expect(decoded.platform == .macOS)
        #expect(decoded.supportedFeatures.count == 2)
    }
    
    @Test("Notification Relay Payload Serialization")
    func testNotificationPayload() throws {
        let action = NotificationActionPayload(actionId: "reply_1", title: "Reply", isReply: true)
        let notif = NotificationRelayPayload(
            notificationId: "notif_123",
            packageName: "com.whatsapp",
            appName: "WhatsApp",
            title: "Alice",
            text: "Hey, see you in 10 minutes!",
            subText: "Family Group",
            actions: [action]
        )
        
        let data = try JSONEncoder().encode(notif)
        let decoded = try JSONDecoder().decode(NotificationRelayPayload.self, from: data)
        
        #expect(decoded.notificationId == "notif_123")
        #expect(decoded.appName == "WhatsApp")
        #expect(decoded.actions.count == 1)
        #expect(decoded.actions.first?.isReply == true)
    }
    
    @Test("Video NALU Serialization and Deserialization")
    func testVideoNALU() {
        let sampleNAL = Data([0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1E])
        let nalu = VideoNALUPayload(nalType: .sps, isKeyframe: true, timestampUs: 1234567, nalData: sampleNAL)
        
        let serialized = nalu.serialize()
        let parsed = VideoNALUPayload.deserialize(from: serialized)
        
        #expect(parsed != nil)
        #expect(parsed?.nalType == .sps)
        #expect(parsed?.isKeyframe == true)
        #expect(parsed?.timestampUs == 1234567)
        #expect(parsed?.nalData == sampleNAL)
    }
    
    @Test("QR Code Generation")
    @MainActor
    func testQRGeneration() {
        let testURL = "http://192.168.1.100:8765"
        let qrImage = QRGenerator.generateQRCode(from: testURL)
        #expect(qrImage != nil)
    }
}
