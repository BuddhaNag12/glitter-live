import CoreMedia
import Foundation

/// The two timed-metadata tracks the Lock Screen requires before it will play a Live Photo as a
/// wallpaper; without them it reports "Motion Not Available". Apple doesn't document these. The
/// layout and the camera reference values come from LivePaper's measurements on a real iPhone
/// (github.com/Yuyang16Z/LivePaper, MIT, see THIRD_PARTY_NOTICES.md). iOS rejects files whose
/// setup values or per-frame payload differ from the camera's, so both are reproduced verbatim.
nonisolated enum LivePhotoMetadata {
    private static let infoKey = "com.apple.quicktime.live-photo-info"
    // The doubled prefix matches what the camera writes.
    private static let infoDataType = "com.apple.quicktime.com.apple.quicktime.live-photo-info"
    private static let stillImageTimeKey = "com.apple.quicktime.still-image-time"
    private static let stillImageTransformKey = "com.apple.quicktime.live-photo-still-image-transform"

    /// QuickTime well-known data types.
    private static let rawDataType: UInt32 = 0
    private static let int8DataType: UInt32 = 0x41
    private static let float64MatrixDataType: UInt32 = 0x53

    /// `live-photo-info`: one sample per video frame.
    static func infoFormatDescription() throws -> CMFormatDescription {
        var dimensions = Data()
        dimensions.appendBigEndian(cameraDimensions.width)
        dimensions.appendBigEndian(cameraDimensions.height)
        let setup = Atom.make("cfgv", cameraSetupPlist) + Atom.make("dims", dimensions)
        let key = keyDeclaration(infoKey)
            + Atom.make("dtyp", reverseDNSType(infoDataType))
            + Atom.make("setu", setup)
            + Atom.make("ctps", Atom.make("dtyp", wellKnownType(rawDataType)))
        return try formatDescription(keys: Atom.make(keyID: 1, key))
    }

    /// `still-image-time` + `live-photo-still-image-transform`: one sample at the cover frame.
    static func stillFormatDescription() throws -> CMFormatDescription {
        let time = keyDeclaration(stillImageTimeKey) + Atom.make("dtyp", wellKnownType(int8DataType))
        let transform = keyDeclaration(stillImageTransformKey) + Atom.make("dtyp", wellKnownType(float64MatrixDataType))
        return try formatDescription(keys: Atom.make(keyID: 1, time) + Atom.make(keyID: 2, transform))
    }

    static func infoSample(format: CMFormatDescription, at time: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        try sample(Atom.make(keyID: 1, cameraInfoPayload), format: format, time: time, duration: duration)
    }

    /// `still-image-time` = -1 plus an identity transform.
    static func stillSample(format: CMFormatDescription, at time: CMTime) throws -> CMSampleBuffer {
        var identity = Data()
        for value in [1.0, 0, 0, 0, 1.0, 0, 0, 0, 1.0] { identity.appendBigEndian(value) }
        let payload = Atom.make(keyID: 1, Data([0xFF])) + Atom.make(keyID: 2, identity)
        return try sample(payload, format: format, time: time, duration: CMTime(value: 1, timescale: 600))
    }

    // MARK: Encoding

    private static func keyDeclaration(_ key: String) -> Data {
        Atom.make("keyd", Data("mdta".utf8) + Data(key.utf8))
    }

    private static func wellKnownType(_ type: UInt32) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(0))
        data.appendBigEndian(type)
        return data
    }

    private static func reverseDNSType(_ type: String) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(1))
        data.append(Data(type.utf8))
        return data
    }

    /// A `mebx` sample description: 6 reserved bytes, data reference index 1, then the key table.
    private static func formatDescription(keys: Data) throws -> CMFormatDescription {
        var body = Data(count: 6)
        body.appendBigEndian(UInt16(1))
        body.append(Atom.make("keys", keys))
        let data = Atom.make("mebx", body)

        var description: CMFormatDescription?
        let status = data.withUnsafeBytes { buffer in
            CMMetadataFormatDescriptionCreateFromBigEndianMetadataDescriptionData(
                allocator: kCFAllocatorDefault,
                bigEndianMetadataDescriptionData: buffer.bindMemory(to: UInt8.self).baseAddress!,
                size: data.count,
                flavor: nil,
                formatDescriptionOut: &description
            )
        }
        guard status == noErr, let description else { throw LivePhotoError.writerFailed(nil) }
        return description
    }

    private static func sample(_ bytes: Data, format: CMFormatDescription, time: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: bytes.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        guard status == noErr, let block else { throw LivePhotoError.writerFailed(nil) }
        status = bytes.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count)
        }
        guard status == noErr else { throw LivePhotoError.writerFailed(nil) }

        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var size = bytes.count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw LivePhotoError.writerFailed(nil) }
        return sample
    }

    // MARK: Camera reference values

    /// The camera's own capture size, kept as is whatever the actual video size.
    private static let cameraDimensions = (width: UInt32(1920), height: UInt32(1440))

    /// Binary plist naming iPhone OS 17.0 (21A5277h) and the capture framework versions.
    private static let cameraSetupPlist = Data(hex:
        "62706c6973743030d301020304050c5f10214c69766550686f746f4d65746164" +
        "61746153657475704461746156657273696f6e5d53797374656d56657273696f" +
        "6e5f10114672616d65776f726b56657273696f6e731001d3060708090a0b5f10" +
        "1350726f647563744275696c6456657273696f6e5b50726f647563744e616d65" +
        "5e50726f6475637456657273696f6e583231413532373768596950686f6e6520" +
        "4f535431372e30d40d0e0f10111213145a436f72654d6f74696f6e5d434d4361" +
        "7074757265436f72655e483130495350536572766963657359436f72654d6564" +
        "696158323836382e302e32573434362e352e335432302e325e333034352e3639" +
        "2e322e31312e340008000f0033004100550057005e00740080008f009800a200" +
        "a700b000bb00c900d800e200eb00f300f8000000000000020100000000000000" +
        "1500000000000000000000000000000107")

    /// One camera-info record, repeated in every frame as the camera does.
    private static let cameraInfoPayload = Data(hex:
        "03000000bdc36d3ce3b5eb6d800000007b80ad425a2d64410a08cb3e7feea6bd" +
        "79e9f63f000080400400ff000000000000000000000000000000000000000000" +
        "07000000525e873ee66e52bf1b2a6ac4d37862bf761ed23dde3f8ec313f52f39" +
        "b2f04439ff309dbf1a17f1ed1b070000206796ed1b0700000000000000000000" +
        "0000000000000000")
}

/// QuickTime atoms are `[size: UInt32][type: 4 bytes][payload]`.
nonisolated private enum Atom {
    static func make(_ fourCC: String, _ payload: Data) -> Data {
        var atom = Data()
        atom.appendBigEndian(UInt32(8 + payload.count))
        atom.append(Data(fourCC.utf8))
        atom.append(payload)
        return atom
    }

    /// Key tables and metadata samples use the local key ID in place of a four-character type.
    static func make(keyID: UInt32, _ payload: Data) -> Data {
        var atom = Data()
        atom.appendBigEndian(UInt32(8 + payload.count))
        atom.appendBigEndian(keyID)
        atom.append(payload)
        return atom
    }
}

nonisolated private extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }

    mutating func appendBigEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: Double) {
        Swift.withUnsafeBytes(of: value.bitPattern.bigEndian) { append(contentsOf: $0) }
    }
}
