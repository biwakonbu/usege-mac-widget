import Foundation

struct InboundMessage {
    let id: String
    let rawJSON: String
    let payload: NativeMessageV1
}

actor HostInboxProcessor {
    func drain() throws -> [InboundMessage] {
        let storedMessages = try HostInboxStore.drainMessages()
        var results: [InboundMessage] = []

        for message in storedMessages {
            guard let rawJSON = String(data: message.rawData, encoding: .utf8) else {
                continue
            }

            guard let payload = try? JSONCoding.decoder.decode(NativeMessageV1.self, from: message.rawData) else {
                continue
            }

            results.append(
                InboundMessage(
                    id: message.id,
                    rawJSON: rawJSON,
                    payload: payload
                )
            )
        }

        return results
    }
}
