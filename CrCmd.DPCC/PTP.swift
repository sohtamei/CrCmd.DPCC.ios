import Foundation

/*
enum PTPContainerType: UInt16 {
    case command  = 0x0001
    case data     = 0x0002
    case response = 0x0003
    case event    = 0x0004
}
*/
struct PTPCommandBuilder {

    static func makeCommand(opCode: UInt16,
                            transactionID: UInt32,
                            params: [UInt32] = []) -> Data {
        let length = UInt32(12 + params.count * 4)

        var data = Data()
        appendLE(length, to: &data)
        appendLE(PTPContainerType.command.rawValue, to: &data)
        appendLE(opCode, to: &data)
        appendLE(transactionID, to: &data)

        for p in params {
            appendLE(p, to: &data)
        }

        return data
    }

    private static func appendLE(_ value: UInt16, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { raw in
            data.append(contentsOf: raw)
        }
    }

    private static func appendLE(_ value: UInt32, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { raw in
            data.append(contentsOf: raw)
        }
    }
}

struct PTPContainer {
    let length: UInt32
    let type: UInt16
    let code: UInt16
    let transactionID: UInt32
    let params: [UInt32]
}

enum PTPParseError: Error, CustomStringConvertible {
    case tooShort
    case invalidLength

    var description: String {
        switch self {
        case .tooShort:
            return "container too short"
        case .invalidLength:
            return "invalid container length"
        }
    }
}

struct PTPParser {

    static func parseContainer(_ data: Data) throws -> PTPContainer {
        guard data.count >= 12 else {
            throw PTPParseError.tooShort
        }

        let length = readUInt32LE(data, offset: 0)
        guard length >= 12, data.count >= Int(length) else {
            throw PTPParseError.invalidLength
        }

        let type = readUInt16LE(data, offset: 4)
        let code = readUInt16LE(data, offset: 6)
        let txid = readUInt32LE(data, offset: 8)

        var params: [UInt32] = []
        var offset = 12
        while offset + 4 <= Int(length) {
            let p = readUInt32LE(data, offset: offset)
            params.append(p)
            offset += 4
        }

        return PTPContainer(
            length: length,
            type: type,
            code: code,
            transactionID: txid,
            params: params
        )
    }

    static func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset])
        | (UInt16(data[offset + 1]) << 8)
    }

    static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
    }

    static func readUInt64LE(_ data: Data, offset: Int) -> UInt64 {
        UInt64(data[offset])
        | (UInt64(data[offset + 1]) << 8)
        | (UInt64(data[offset + 2]) << 16)
        | (UInt64(data[offset + 3]) << 24)
        | (UInt64(data[offset + 4]) << 32)
        | (UInt64(data[offset + 5]) << 40)
        | (UInt64(data[offset + 6]) << 48)
        | (UInt64(data[offset + 7]) << 56)
    }
}

extension Data {
    func hexDump(separator: String = " ") -> String {
        self.map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}
