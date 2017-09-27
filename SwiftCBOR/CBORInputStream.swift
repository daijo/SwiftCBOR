public protocol CBORInputStream {
    func popByte() throws -> (byte: UInt8, rest: CBORInputStream)
    func popBytes(_ n: Int) throws -> (bytes: ArraySlice<UInt8>, rest: CBORInputStream)
}

// FUCK: https://openradar.appspot.com/23255436
struct ArraySliceUInt8 {
	var slice : ArraySlice<UInt8>
}

struct ArrayUInt8 {
    var array : Array<UInt8>
}

extension ArraySliceUInt8: CBORInputStream {

    func popByte() throws -> (byte: UInt8, rest: CBORInputStream) {
		if slice.count < 1 { throw CBORError.unfinishedSequence }
        return (byte: slice.first!, rest:ArraySliceUInt8(slice: slice.dropFirst(1)))
	}

    func popBytes(_ n: Int) throws -> (bytes: ArraySlice<UInt8>, rest: CBORInputStream) {
		if slice.count < n { throw CBORError.unfinishedSequence }
		let result = slice.prefix(n)
        return (bytes: result, rest: ArraySliceUInt8(slice: slice.dropFirst(n)))
	}

}

extension ArrayUInt8: CBORInputStream {

    func popByte() throws -> (byte: UInt8, rest: CBORInputStream) {
        guard array.count > 0 else { throw CBORError.unfinishedSequence }
        return (byte: array.first!, rest: ArrayUInt8(array: Array(array.dropFirst(1))))
    }

    func popBytes(_ n: Int) throws -> (bytes: ArraySlice<UInt8>, rest: CBORInputStream) {
        guard array.count >= n else { throw CBORError.unfinishedSequence }
        let result = array.prefix(n)
        return (bytes: result, rest: ArrayUInt8(array: Array(array.dropFirst(n))))
    }

}
