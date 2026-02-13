import Foundation

private enum HostRuntimeError: Error {
    case invalidLength
    case invalidPayload(String)
}

private func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
    var data = Data()
    while data.count < count {
        let remaining = count - data.count
        let chunk = try handle.read(upToCount: remaining) ?? Data()
        if chunk.isEmpty {
            throw HostRuntimeError.invalidLength
        }
        data.append(chunk)
    }
    return data
}

private func readMessage(from handle: FileHandle) throws -> Data? {
    let lengthData = try handle.read(upToCount: 4) ?? Data()
    if lengthData.isEmpty {
        return nil
    }
    if lengthData.count < 4 {
        throw HostRuntimeError.invalidLength
    }

    let length = lengthData.withUnsafeBytes { rawPtr -> UInt32 in
        rawPtr.load(as: UInt32.self)
    }

    if length == 0 {
        return Data()
    }

    return try readExactly(Int(length), from: handle)
}

private func writeMessage(_ data: Data, to handle: FileHandle) throws {
    var length = UInt32(data.count).littleEndian
    let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
    try handle.write(contentsOf: lengthData)
    try handle.write(contentsOf: data)
}

private func buildErrorResponse(code: SyncErrorCode, message: String) -> NativeHostResponse {
    NativeHostResponse(
        v: 1,
        ok: false,
        acceptedAt: Date(),
        snapshotID: nil,
        errorCode: code,
        errorMessage: message
    )
}

private func processPayload(_ payloadData: Data) -> NativeHostResponse {
    do {
        let payload = try JSONCoding.decoder.decode(NativeMessageV1.self, from: payloadData)

        guard payload.v == 1 else {
            return buildErrorResponse(code: .invalidPayload, message: "Unsupported version")
        }

        if payload.type == "usage_snapshot" {
            guard payload.provider != nil, payload.metrics != nil, payload.capturedAt != nil else {
                return buildErrorResponse(code: .invalidPayload, message: "Incomplete usage_snapshot payload")
            }
        }

        if payload.type == "sync_error" {
            guard payload.provider != nil, payload.errorCode != nil else {
                return buildErrorResponse(code: .invalidPayload, message: "Incomplete sync_error payload")
            }
        }

        let snapshotID = try HostInboxStore.persistInboundMessage(payloadData)
        return NativeHostResponse(
            v: 1,
            ok: true,
            acceptedAt: Date(),
            snapshotID: snapshotID,
            errorCode: nil,
            errorMessage: nil
        )
    } catch {
        return buildErrorResponse(code: .invalidPayload, message: error.localizedDescription)
    }
}

let input = FileHandle.standardInput
let output = FileHandle.standardOutput

while true {
    do {
        guard let payloadData = try readMessage(from: input) else {
            break
        }

        let response = processPayload(payloadData)
        let responseData = try JSONCoding.encoder.encode(response)
        try writeMessage(responseData, to: output)
    } catch {
        let response = buildErrorResponse(code: .unknown, message: error.localizedDescription)
        if let responseData = try? JSONCoding.encoder.encode(response) {
            try? writeMessage(responseData, to: output)
        }
        break
    }
}
