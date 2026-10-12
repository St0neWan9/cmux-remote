import Darwin
import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteMac

@Suite struct TerminalOutputTests {
    @Test func stalledOutputHasBoundedDeadline() throws {
        var descriptors: [Int32] = [0, 0]
        try #require(pipe(&descriptors) == 0)
        let readerFD = descriptors[0], writerFD = descriptors[1]
        defer { Darwin.close(readerFD); Darwin.close(writerFD) }
        _ = fcntl(writerFD, F_SETFL, fcntl(writerFD, F_GETFL) | O_NONBLOCK)
        let bytes = [UInt8](repeating: 0x61, count: 8192)
        while bytes.withUnsafeBytes({ Darwin.write(writerFD, $0.baseAddress, $0.count) }) > 0 {}
        try #require(errno == EAGAIN)
        let clock = ContinuousClock(), began = ContinuousClock().now
        #expect(throws: BridgeError.self) {
            try TerminalOutputWriter(descriptor: writerFD, timeout: .milliseconds(10)).write(Data([0x62]))
        }
        #expect(clock.now - began < .seconds(1))
    }
    @Test func nonblockingOutputSurvivesFrameLargerThanTerminalBuffer() async throws {
        var descriptors: [Int32] = [0, 0]
        try #require(pipe(&descriptors) == 0)
        let readerFD = descriptors[0], writerFD = descriptors[1]
        defer { Darwin.close(readerFD) }
        _ = fcntl(writerFD, F_SETFL, fcntl(writerFD, F_GETFL) | O_NONBLOCK)
        let payload = Data(repeating: 0x61, count: 1_048_576)
        let drained = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(1))
        // Start the drain outside the cooperative pool before this test blocks on writing.
        DispatchQueue.global(qos: .userInitiated).async {
            var received = Data(), chunk = [UInt8](repeating: 0, count: 64)
            while true {
                let count = Darwin.read(readerFD, &chunk, chunk.count)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { break }
                received.append(contentsOf: chunk.prefix(count))
            }
            drained.continuation.yield(received); drained.continuation.finish()
        }
        var failure: (any Error)?
        do { try TerminalOutputWriter(descriptor: writerFD).write(payload) }
        catch { failure = error }
        Darwin.close(writerFD)
        var iterator = drained.stream.makeAsyncIterator()
        let received = await iterator.next()
        if let failure { throw failure }
        #expect(received == payload)
    }
}
