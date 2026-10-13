import Foundation
import CmuxRemoteCore
@testable import CmuxRemoteClient

/// A fixture deliberately controls acknowledgements and signed request ownership.
struct LinkRawConnection {
    let socket: LinkSocket
    var cipher: LinkCipher
    let epoch: String
    static func connect(_ connection: AuthorizedConnection, signingKey: Data? = nil) async throws -> LinkRawConnection {
        let endpoint = connection.endpoint
        let pairing = try PairingConfiguration(host: endpoint.host, port: endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: connection.host.certificateSHA256)
        var components = URLComponents(); components.scheme = "wss"; components.host = endpoint.host; components.port = endpoint.port; components.path = "/v3/link"
        let socket = LinkSocket(url: components.url!, delegate: PinnedSessionDelegate(pairing: pairing))
        do {
            let handshake = try LinkClientHandshake(host: connection.host, privateKey: signingKey ?? connection.privateKey)
            try await socket.send(JSONEncoder().encode(handshake.proposal))
            let accepted = try JSONDecoder().decode(SignedValue<LinkAcceptance>.self, from: await socket.receive())
            return LinkRawConnection(socket: socket, cipher: try handshake.accept(accepted), epoch: accepted.value.epoch)
        } catch { socket.close(); throw error }
    }
    mutating func read(_ path: String, connection: AuthorizedConnection) async throws -> String {
        let id = UUID().uuidString, crypto = IdentityCryptography()
        let proof = RequestProof(epoch: epoch, hostID: connection.host.id, clientID: connection.grant.value.clientID, method: "GET", uri: path, bodySHA256: crypto.digest(Data()), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
        let authorization = "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: connection.privateKey))).base64EncodedString()
        let bytes = try cipher.seal(LinkFrame(kind: "request", id: id, method: "GET", uri: path, authorization: authorization))
        try await socket.send(bytes); return id
    }
    mutating func next() async throws -> LinkFrame { try cipher.open(await socket.receive()) }
    mutating func ack(_ frame: LinkFrame) async throws { try await socket.send(cipher.seal(LinkFrame(kind: "ack", id: frame.id, index: frame.index))) }
}
