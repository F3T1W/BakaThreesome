import Foundation
import ShikimoriBridge
import Testing

@Test func handshakeResponseMatchesDotNetContract() throws {
    let json = #"{"version":1,"id":"smoke","result":{"name":"BakaThreesome.ShikimoriBridge","capabilities":["handshake"]},"error":null}"#
    let response = try JSONDecoder().decode(BridgeResponse.self, from: Data(json.utf8))
    #expect(response.version == 1)
    #expect(response.id == "smoke")
    #expect(response.result?.capabilities == ["handshake"])
    #expect(response.error == nil)
}
