public enum CBORError : Error {
	case unfinishedSequence
	case wrongTypeInsideSequence
	case incorrectUTF8String
}

extension CBOR {
    static func decode(_ input: [UInt8]) throws -> CBOR? {
        return try CBORDecoder(input: input).decodeItem()
    }
}

public class CBORDecoder {

	private var istream : CBORInputStream

	public init(stream: CBORInputStream) {
		istream = stream
	}

	public init(input: ArraySlice<UInt8>) {
		istream = ArraySliceUInt8(slice: input)
	}

	public init(input: [UInt8]) {
		istream = ArrayUInt8(array: input)
	}

	static func readUInt<T: UnsignedInteger>(_ n: Int, from stream: CBORInputStream) throws -> (T, CBORInputStream) {
        let result = try stream.popBytes(n)
        return (UnsafeRawPointer(Array(result.bytes.reversed())).load(as: T.self), result.rest)
	}

    static func readN(_ n: Int, initial: [CBOR], from stream: CBORInputStream) throws -> ([CBOR], CBORInputStream) {

        guard n > 0 else {
            return (initial, stream)
        }

        let current = try CBORDecoder.decodeStream(stream: stream)

        guard let newCbor = current.cbor, let rest = current.rest else {
            throw CBORError.unfinishedSequence
        }

        return try CBORDecoder.readN(n - 1, initial: initial + [newCbor], from: rest)
	}

	static func readUntilBreak(initial: [CBOR], from stream: CBORInputStream) throws -> ([CBOR], CBORInputStream) {

		let current = try CBORDecoder.decodeStream(stream: stream)

        guard let cbor = current.cbor, let rest = current.rest else {
            throw CBORError.unfinishedSequence
        }

        guard cbor != CBOR.break else {
            return (initial, rest)
        }

		return try CBORDecoder.readUntilBreak(initial: initial + [cbor], from: rest)
	}

	static func readNPairs(_ n: Int, initial: [CBOR : CBOR], from stream: CBORInputStream) throws -> ([CBOR : CBOR], CBORInputStream) {

        guard n > 0 else {
            return (initial, stream)
        }

        let key = try CBORDecoder.decodeStream(stream: stream)

        guard let keyCbor = key.cbor, let keyRest = key.rest else {
            throw CBORError.unfinishedSequence
        }

        let value = try CBORDecoder.decodeStream(stream: keyRest)

        guard let valueCbor = value.cbor, let valueRest = value.rest else {
            throw CBORError.unfinishedSequence
        }

        var result = initial
        result[keyCbor] = valueCbor

        return try CBORDecoder.readNPairs(n - 1, initial: result, from: valueRest)
	}

	static func readPairsUntilBreak(initial: [CBOR : CBOR], from stream: CBORInputStream) throws -> ([CBOR : CBOR], CBORInputStream) {

        let key = try CBORDecoder.decodeStream(stream: stream)

        guard let keyCbor = key.cbor, let keyRest = key.rest else {
            throw CBORError.unfinishedSequence
        }

        guard (keyCbor != CBOR.break) else { return (initial, keyRest) } // don't eat the val after the break!

        let value = try CBORDecoder.decodeStream(stream: keyRest)

        guard let valueCbor = value.cbor, let valueRest = value.rest else {
            throw CBORError.unfinishedSequence
        }

        var result = initial
        result[keyCbor] = valueCbor

        return try CBORDecoder.readPairsUntilBreak(initial: result, from: valueRest)
	}

    public func decodeItem() throws -> CBOR? {
        return try CBORDecoder.decodeStream(stream: istream).cbor
	}

    static func decodeStream(stream: CBORInputStream) throws -> (cbor: CBOR?, rest: CBORInputStream?) {

        let next = try stream.popByte()

        switch next.byte {
        case let b where b <= 0x17: return (CBOR.unsignedInt(UInt(b)), next.rest)
        case 0x18:
            let next = try next.rest.popByte()
            return (CBOR.unsignedInt(UInt(next.byte)), next.rest)
        case 0x19:
            let next = try CBORDecoder.readUInt(2, from: next.rest) as (UInt16, CBORInputStream)
            return (CBOR.unsignedInt(UInt(next.0)), next.1)
        case 0x1a:
            let next = try CBORDecoder.readUInt(4, from: next.rest) as (UInt32, CBORInputStream)
            return (CBOR.unsignedInt(UInt(next.0)), next.1)
        case 0x1b:
            let next = try CBORDecoder.readUInt(8, from: next.rest) as (UInt64, CBORInputStream)
            return (CBOR.unsignedInt(UInt(next.0)), next.1)

        case let b where 0x20 <= b && b <= 0x37: return (CBOR.negativeInt(UInt(b - 0x20)), next.rest)
        case 0x38:
            let next = try next.rest.popByte()
            return (CBOR.negativeInt(UInt(next.byte)), next.rest)
        case 0x39:
            let next = try CBORDecoder.readUInt(2, from: next.rest) as (UInt16, CBORInputStream)
            return (CBOR.negativeInt(UInt(next.0)), next.1)
        case 0x3a:
            let next = try CBORDecoder.readUInt(4, from: next.rest) as (UInt32, CBORInputStream)
            return (CBOR.negativeInt(UInt(next.0)), next.1)
        case 0x3b:
            let next = try CBORDecoder.readUInt(8, from: next.rest) as (UInt64, CBORInputStream)
            return (CBOR.negativeInt(UInt(next.0)), next.1)

        case let b where 0x40 <= b && b <= 0x57:
            let next = try next.rest.popBytes(Int(b - 0x40))
            return (CBOR.byteString(Array(next.bytes)), next.rest)
        case 0x58:
            let length = try next.rest.popByte()
            let bytes = try length.rest.popBytes(Int(length.byte))
            return (CBOR.byteString(Array(bytes.bytes)), bytes.rest)
        case 0x59:
            let length = try CBORDecoder.readUInt(2, from: next.rest) as (UInt16, CBORInputStream)
            let bytes = try length.1.popBytes(Int(length.0))
            return (CBOR.byteString(Array(bytes.bytes)), bytes.rest)
        case 0x5a:
            let length = try CBORDecoder.readUInt(4, from: next.rest) as (UInt32, CBORInputStream)
            let bytes = try length.1.popBytes(Int(length.0))
            return (CBOR.byteString(Array(bytes.bytes)), bytes.rest)
        case 0x5b:
            let length = try CBORDecoder.readUInt(8, from: next.rest) as (UInt64, CBORInputStream)
            let bytes = try length.1.popBytes(Int(length.0))
            return (CBOR.byteString(Array(bytes.bytes)), bytes.rest)
        case 0x5f:
            let array = try CBORDecoder.readUntilBreak(initial: [], from: next.rest)
            return (CBOR.byteString(try array.0.flatMap { x -> [UInt8] in guard case .byteString(let r) = x else { throw CBORError.wrongTypeInsideSequence }; return r }), array.1)

        case let b where 0x60 <= b && b <= 0x77:
            let chars = try next.rest.popBytes(Int(b - 0x60))
            return (CBOR.utf8String(try Util.decodeUtf8(chars.bytes)), chars.rest)
        case 0x78:
            let length = try next.rest.popByte()
            let chars = try length.rest.popBytes(Int(length.byte))
            return (CBOR.utf8String(try Util.decodeUtf8(chars.bytes)), chars.rest)
        case 0x79:
            let length = try CBORDecoder.readUInt(2, from: next.rest) as (UInt16, CBORInputStream)
            let chars = try length.1.popBytes(Int(length.0))
            return (CBOR.utf8String(try Util.decodeUtf8(chars.bytes)), chars.rest)
        case 0x7a:
            let length = try CBORDecoder.readUInt(4, from: next.rest) as (UInt32, CBORInputStream)
            let chars = try length.1.popBytes(Int(length.0))
            return (CBOR.utf8String(try Util.decodeUtf8(chars.bytes)), chars.rest)
        case 0x7b:
            let length = try CBORDecoder.readUInt(8, from: next.rest) as (UInt64, CBORInputStream)
            let chars = try length.1.popBytes(Int(length.0))
            return (CBOR.utf8String(try Util.decodeUtf8(chars.bytes)), chars.rest)
        case 0x7f:
            let chars = try CBORDecoder.readUntilBreak(initial: [], from: next.rest)
            return (CBOR.utf8String(try chars.0.map { x -> String in guard case .utf8String(let r) = x else { throw CBORError.wrongTypeInsideSequence }; return r }.joined(separator: "")), chars.1)

        case let b where 0x80 <= b && b <= 0x97:
            let array = try CBORDecoder.readN(Int(b - 0x80), initial: [], from: next.rest)
            return (CBOR.array(array.0), array.1)
        case 0x98:
            let length = try next.rest.popByte()
            let array = try CBORDecoder.readN(Int(length.byte), initial: [], from: length.rest)
            return (CBOR.array(array.0), array.1)
        case 0x99:
            let length = try CBORDecoder.readUInt(2, from: next.rest) as (UInt16, CBORInputStream)
            let array = try CBORDecoder.readN(Int(length.0), initial: [], from: length.1)
            return (CBOR.array(array.0), array.1)
        case 0x9a:
            let length = try CBORDecoder.readUInt(4, from: next.rest) as (UInt32, CBORInputStream)
            let array = try CBORDecoder.readN(Int(length.0), initial: [], from: length.1)
            return (CBOR.array(array.0), array.1)
        case 0x9b:
            let length = try CBORDecoder.readUInt(8, from: next.rest) as (UInt64, CBORInputStream)
            let array = try CBORDecoder.readN(Int(length.0), initial: [], from: length.1)
            return (CBOR.array(array.0), array.1)
        case 0x9f:
            let array = try CBORDecoder.readUntilBreak(initial: [], from: next.rest)
            return (CBOR.array(array.0), array.1)

        case let b where 0xa0 <= b && b <= 0xb7:
            let pairs = try CBORDecoder.readNPairs(Int(b - 0xa0), initial: [:], from: next.rest)
            return (CBOR.map(pairs.0), pairs.1)
        case 0xb8:
            let length = try next.rest.popByte()
            let pairs = try CBORDecoder.readNPairs(Int(length.byte), initial: [:], from: length.rest)
            return (CBOR.map(pairs.0), pairs.1)
        case 0xb9:
            let length = try CBORDecoder.readUInt(2, from: next.rest) as (UInt16, CBORInputStream)
            let pairs = try CBORDecoder.readNPairs(Int(length.0), initial: [:], from: length.1)
            return (CBOR.map(pairs.0), pairs.1)
        case 0xba:
            let length = try CBORDecoder.readUInt(4, from: next.rest) as (UInt32, CBORInputStream)
            let pairs = try CBORDecoder.readNPairs(Int(length.0), initial: [:], from: length.1)
            return (CBOR.map(pairs.0), pairs.1)
        case 0xbb:
            let length = try CBORDecoder.readUInt(8, from: next.rest) as (UInt64, CBORInputStream)
            let pairs = try CBORDecoder.readNPairs(Int(length.0), initial: [:], from: length.1)
            return (CBOR.map(pairs.0), pairs.1)
        case 0xbf:
            let pairs = try CBORDecoder.readPairsUntilBreak(initial: [:], from: next.rest)
            return (CBOR.map(pairs.0), pairs.1)

        case let b where 0xc0 <= b && b <= 0xd7:
            let item = try CBORDecoder.decodeStream(stream: next.rest)
            guard let itemCbor = item.cbor else { throw CBORError.unfinishedSequence }
            return (CBOR.tagged(UInt8(b - 0xc0), itemCbor), item.rest)
        case 0xd8:
            let next = try next.rest.popByte()
            let tag = UInt8(next.0)
            let item = try CBORDecoder.decodeStream(stream: next.1)
            guard let itemCbor = item.cbor else { throw CBORError.unfinishedSequence }
            return (CBOR.tagged(tag, itemCbor), item.rest)
        case 0xd9:
            let next = try CBORDecoder.readUInt(2, from: next.rest) as (UInt16, CBORInputStream)
            let tag = UInt8(next.0)
            let item = try CBORDecoder.decodeStream(stream: next.1)
            guard let itemCbor = item.cbor else { throw CBORError.unfinishedSequence }
            return (CBOR.tagged(tag, itemCbor), item.rest)
        case 0xda:
            let next = try CBORDecoder.readUInt(4, from: stream) as (UInt32, CBORInputStream)
            let tag = UInt8(next.0)
            let item = try CBORDecoder.decodeStream(stream: next.1)
            guard let itemCbor = item.cbor else { throw CBORError.unfinishedSequence }
            return (CBOR.tagged(tag, itemCbor), item.rest)
        case 0xdb:
            let next = try CBORDecoder.readUInt(8, from: next.rest) as (UInt64, CBORInputStream)
            let tag = UInt8(next.0)
            let item = try CBORDecoder.decodeStream(stream: next.1)
            guard let itemCbor = item.cbor else { throw CBORError.unfinishedSequence }
            return (CBOR.tagged(tag, itemCbor), item.rest)

        case let b where 0xe0 <= b && b <= 0xf3: return (CBOR.simple(b - 0xe0), next.rest)
        case 0xf4: return (CBOR.boolean(false), next.rest)
        case 0xf5: return (CBOR.boolean(true), next.rest)
        case 0xf6: return (CBOR.null, next.rest)
        case 0xf7: return (CBOR.undefined, next.rest)
        case 0xf8:
            let next = try next.rest.popByte()
            return (CBOR.simple(next.byte), next.rest)
        case 0xf9:
            let next = try next.rest.popBytes(2)
            let ptr = UnsafeRawPointer(Array(next.bytes.reversed())).bindMemory(to: UInt16.self, capacity: 1)
            return (CBOR.half(loadFromF16(ptr)), next.rest)
        case 0xfa:
            let next = try next.rest.popBytes(4)
            return (CBOR.float(UnsafeRawPointer(Array(next.bytes.reversed())).load(as: Float32.self)), next.rest)
        case 0xfb:
            let next = try next.rest.popBytes(8)
            return (CBOR.double(UnsafeRawPointer(Array(next.bytes.reversed())).load(as: Float64.self)), next.rest)
        case 0xff: return (CBOR.break, next.rest)
        default: return (nil, nil)
        }
    }
}
