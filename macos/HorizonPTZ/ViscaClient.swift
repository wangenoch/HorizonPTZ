import Foundation
import Network

class ViscaClient {
    private let ipAddress: String
    private let port: UInt16
    private var sequenceNumber: UInt32 = 0
    private let queue = DispatchQueue(label: "com.horizon.visca")
    
    private static let PAYLOAD_TYPE_COMMAND: [UInt8] = [0x01, 0x00]
    private static let PAYLOAD_TYPE_INQUIRY: [UInt8] = [0x01, 0x10]
    private static let HEADER_SIZE = 8
    
    init(config: CameraConfig) {
        self.ipAddress = config.ipAddress
        self.port = UInt16(config.controlPort)
    }
    
    func sendCommand(payload: [UInt8], isInquiry: Bool = false) {
        let seq = sequenceNumber
        sequenceNumber += 1
        let packetData = buildPacket(payload: payload, isInquiry: isInquiry, seq: seq)
        
        let host = NWEndpoint.Host(ipAddress)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        
        let connection = NWConnection(host: host, port: endpointPort, using: .udp)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: Data(packetData), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }
    
    private func buildPacket(payload: [UInt8], isInquiry: Bool, seq: UInt32) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: Self.HEADER_SIZE + payload.count)
        
        // Byte 0-1: Payload Type
        let type = isInquiry ? Self.PAYLOAD_TYPE_INQUIRY : Self.PAYLOAD_TYPE_COMMAND
        packet[0] = type[0]
        packet[1] = type[1]
        
        // Byte 2-3: Payload Length
        packet[2] = UInt8((payload.count >> 8) & 0xFF)
        packet[3] = UInt8(payload.count & 0xFF)
        
        // Byte 4-7: Sequence Number
        packet[4] = UInt8((seq >> 24) & 0xFF)
        packet[5] = UInt8((seq >> 16) & 0xFF)
        packet[6] = UInt8((seq >> 8) & 0xFF)
        packet[7] = UInt8(seq & 0xFF)
        
        // Payload
        for i in 0..<payload.count {
            packet[Self.HEADER_SIZE + i] = payload[i]
        }
        
        return packet
    }
    
    /// Sends PTZ movement command.
    /// - Parameters:
    ///   - panSpeed: Horizontal speed (0x01-0x18)
    ///   - tiltSpeed: Vertical speed (0x01-0x14)
    ///   - panMode: 0: stop, 1: left, 2: right
    ///   - tiltMode: 0: stop, 1: up, 2: down
    func sendPtzCommand(panSpeed: Int, tiltSpeed: Int, panMode: Int, tiltMode: Int) {
        var payload = [UInt8](repeating: 0, count: 9)
        payload[0] = 0x81
        payload[1] = 0x01
        payload[2] = 0x06
        payload[3] = 0x01
        payload[4] = UInt8(panSpeed & 0xFF)
        payload[5] = UInt8(tiltSpeed & 0xFF)
        
        // Byte 6: Pan (01: Left, 02: Right, 03: Stop)
        payload[6] = (panMode == 1) ? 0x01 : ((panMode == 2) ? 0x02 : 0x03)
        
        // Byte 7: Tilt (01: Up, 02: Down, 03: Stop)
        payload[7] = (tiltMode == 1) ? 0x01 : ((tiltMode == 2) ? 0x02 : 0x03)
        
        payload[8] = 0xFF
        sendCommand(payload: payload)
    }
    
    /// Sends Zoom command.
    /// - Parameters:
    ///   - mode: 0: stop, 1: zoom in (Tele), 2: zoom out (Wide)
    ///   - speed: Speed (0-7)
    func sendZoomCommand(mode: Int, speed: Int) {
        var payload = [UInt8](repeating: 0, count: 6)
        payload[0] = 0x81
        payload[1] = 0x01
        payload[2] = 0x04
        payload[3] = 0x07
        
        payload[4] = (mode == 1) ? (0x20 | UInt8(speed & 0x07)) : ((mode == 2) ? (0x30 | UInt8(speed & 0x07)) : 0x00)
        payload[5] = 0xFF
        
        sendCommand(payload: payload)
    }
    
    /// Sends Preset command.
    /// - Parameters:
    ///   - mode: 1: Set, 2: Recall
    ///   - presetIndex: Preset slot number (1-127)
    func sendPresetCommand(mode: Int, presetIndex: Int) {
        let payload: [UInt8] = [
            0x81, 0x01, 0x04, 0x3F,
            UInt8(mode & 0xFF),
            UInt8(presetIndex & 0xFF),
            0xFF
        ]
        sendCommand(payload: payload)
    }
}
