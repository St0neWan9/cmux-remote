import Foundation
import NIOCore
import NIOPosix
import CmuxRemoteCore

/// One separately owned cmux event connection, never used for request RPCs.
public struct CmuxEventClient: Sendable {
    private let path: String
    private let password: String?
    public init(path: String, password: String? = nil) { self.path = path; self.password = password }
    public func consume(afterSequence: Int?, onFrame: @escaping @Sendable (JSONValue) async throws -> Void) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let frames = AsyncThrowingStream<JSONValue, any Error>.makeStream(bufferingPolicy: .bufferingOldest(256))
        let password = password
        let subscription: JSONValue = .object(["id": .string(UUID().uuidString), "method": .string("events.stream"), "params": .object(["categories": .array(["workspace", "surface", "agent", "feed"].map(JSONValue.string)), "after_seq": afterSequence.map { .number(Double($0)) } ?? .null])])
        do {
            let channel = try await ClientBootstrap(group: group).connectTimeout(.seconds(5)).channelInitializer { channel in
                channel.pipeline.addHandler(CmuxEventHandler(subscription: subscription, password: password, continuation: frames.continuation))
            }.connect(unixDomainSocketPath: path).get()
            do {
                try await withTaskCancellationHandler {
                    for try await frame in frames.stream { try Task.checkCancellation(); try await onFrame(frame) }
                } onCancel: { channel.close(promise: nil) }
                try await channel.close().get()
            } catch { try? await channel.close().get(); throw error }
            try await group.shutdownGracefully()
        } catch { try? await group.shutdownGracefully(); throw error }
    }
}
