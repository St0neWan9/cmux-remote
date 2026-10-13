import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Resolves local services once; daemon discovery continues in the aggregate controller.
struct SourceBackends {
    let controller: any CmuxControlling
    let desktop: (any CmuxControlling)?
    let desktopSocket: String?
    init(options: CLIOptions, environment: [String: String], home: URL, transcripts: TuiTranscriptLocator, directory: URL?, mutations: MutationLedger) async throws {
        var local: (any CmuxControlling)?, path: String?
        if let socket = try? SocketDiscovery().resolve(explicit: options.value("socket"), environment: environment, home: home) {
            let cli = options.value("cli") ?? "/Applications/cmux.app/Contents/Resources/bin/cmux"
            let candidate: any CmuxControlling = !options.contains("direct-socket") && FileManager.default.isExecutableFile(atPath: cli)
                ? CLIControlClient(executable: URL(fileURLWithPath: cli), socketPath: socket, environment: environment)
                : UnixSocketClient(path: socket, password: environment["CMUX_REMOTE_SOCKET_PASSWORD"], capability: environment["CMUX_SOCKET_CAPABILITY"])
            if (try? await candidate.request("system.ping", params: [:])) != nil { local = candidate; path = socket }
        }
        desktop = local; desktopSocket = path
        controller = CmuxBackendRouter(desktop: local, discovery: TuiSocketDiscovery(explicit: options.values("tui-socket"))) { socket in
            TuiControlAdapter(client: TuiResourceSocketClient(path: socket), transcripts: transcripts, attachments: directory.map { TuiAttachmentStore(directory: $0) }, decisions: mutations, archive: directory.map { TuiBindingRepository(directory: $0) })
        }
        _ = try await controller.request("system.ping", params: [:])
    }
}
