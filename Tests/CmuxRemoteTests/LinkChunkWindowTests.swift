import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge
@testable import CmuxRemoteClient

/// A relayed response pays one round trip per window of chunks; the window stays bounded and ordered.
@Suite struct LinkChunkWindowTests {
    @Test(.timeLimit(.minutes(1)))
    func aLargeResponseKeepsAtMostAWindowOfChunksUnacknowledged() async throws {
        let fixture = try await LinkIntegrationFixture.create(text: String(repeating: "windowed ", count: 30_000), recordCount: 24)
        var raw: LinkRawConnection?
        do {
            var connection = try await LinkRawConnection.connect(fixture.connection); raw = connection
            let id = try await connection.read("/v2/sessions/demo-session/history", connection: fixture.connection)
            // Without any acknowledgement the Bridge sends exactly one window of four chunks, then waits.
            #expect(LinkServerSession.chunkWindow == 4)
            var held: [LinkFrame] = []
            for _ in 0..<LinkServerSession.chunkWindow { held.append(try await connection.next()) }
            #expect(held.map(\.id) == Array(repeating: id, count: LinkServerSession.chunkWindow))
            #expect(held.map(\.index) == Array(0..<LinkServerSession.chunkWindow))
            #expect(held.allSatisfy { $0.final == false })
            // With the window full, the next frame is a cheap read's answer, not chunk four of the stalled one.
            let other = try await connection.read("/v2/sessions", connection: fixture.connection)
            let answer = try await connection.next(); #expect(answer.id == other); #expect(answer.final == true)
            try await connection.ack(answer)
            // Each acknowledgement releases exactly one more chunk, in order, until the final one.
            var received = held, acknowledged = 0
            while received.last?.final != true {
                try await connection.ack(received[acknowledged]); acknowledged += 1
                let frame = try await connection.next()
                #expect(frame.id == id); #expect(frame.index == received.count); received.append(frame)
            }
            #expect(received.count > 4)
            for frame in received[acknowledged...] { try await connection.ack(frame) }
            let body = received.compactMap(\.data).reduce(Data(), +)
            // The reassembled chunks are one complete response, whatever page of history the Bridge chose.
            #expect(try !JSONDecoder().decode(ConversationSnapshot.self, from: body).messages.isEmpty)
            connection.socket.close(); await fixture.stop()
        } catch { raw?.socket.close(); await fixture.stop(); throw error }
    }
    @Test(.timeLimit(.minutes(1)))
    func anAcknowledgementOutOfOrderEndsTheLink() async throws {
        let fixture = try await LinkIntegrationFixture.create(text: String(repeating: "ordered ", count: 30_000), recordCount: 8)
        var raw: LinkRawConnection?
        do {
            var connection = try await LinkRawConnection.connect(fixture.connection); raw = connection
            _ = try await connection.read("/v2/sessions/demo-session/history", connection: fixture.connection)
            _ = try await connection.next()
            let second = try await connection.next(); #expect(second.index == 1)
            // Acknowledging chunk one before chunk zero is a protocol violation, not a skip: the link closes
            // at once instead of waiting out the twenty-second consumer deadline.
            let clock = ContinuousClock(), sent = clock.now
            try await connection.ack(second)
            do {
                while true { _ = try await connection.next() }
            } catch {}
            #expect(clock.now - sent < .seconds(5))
            connection.socket.close(); await fixture.stop()
        } catch { raw?.socket.close(); await fixture.stop(); throw error }
    }
}
