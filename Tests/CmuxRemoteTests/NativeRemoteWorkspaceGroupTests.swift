import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteMac

private actor NativeGroupFixture: CmuxControlling {
    let window = "99999999-9999-9999-9999-999999999999"
    let first = "11111111-1111-1111-1111-111111111111"
    let second = "22222222-2222-2222-2222-222222222222"
    let mirror = "33333333-3333-3333-3333-333333333333"
    let anchor = "44444444-4444-4444-4444-444444444444"
    let groupID = "55555555-5555-5555-5555-555555555555"
    var order: [String] = []
    var owned: JSONValue?
    var calls: [String] = []
    var creates = 0
    var lostCreate = false
    var manual: JSONValue = .object(["id": .string("66666666-6666-6666-6666-666666666666"), "name": .string("Remote")])
    init() { order = [first, mirror, second] }
    func loseCreateReceipt() { lostCreate = true }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        calls.append(method)
        #expect(params["window_id"]?.string == window)
        #expect(params["focus"]?.bool != true)
        switch method {
        case "workspace.list": return .object(["workspaces": .array(order.map { .object(["id": .string($0)]) })])
        case "workspace.group.list": return .object(["window_id": .string(window), "groups": .array([manual] + (owned.map { [$0] } ?? []))])
        case "workspace.group.create":
            creates += 1
            #expect(params["child_workspace_ids"]?.array?.isEmpty == true)
            owned = .object(["id": .string(groupID), "name": .string("Remote"), "external_id": params["external_id"]!,
                "anchor_workspace_id": .string(anchor), "member_workspace_ids": .array([.string(anchor)])])
            order.append(anchor)
            if lostCreate { lostCreate = false; throw BridgeError("outcome_unknown", "Group created; receipt lost") }
            return .object(["group": owned!])
        case "workspace.group.add":
            #expect(params["group_id"]?.string == groupID)
            #expect(params["workspace_id"]?.string == mirror)
            var object = owned!.object!; object["member_workspace_ids"] = .array([.string(anchor), .string(mirror)]); owned = .object(object)
            return .object([:])
        case "workspace.reorder_many": order = params["workspace_ids"]!.array!.compactMap(\.string); return .object([:])
        default: throw BridgeError("not_found", "Unexpected group operation")
        }
    }
}

@Suite struct NativeRemoteWorkspaceGroupTests {
    @Test func nativeGroupFollowsLocalRowsWithoutAdoptingSameNamedUserGroup() async throws {
        let local = NativeGroupFixture(), service = NativeRemoteWorkspaceGroup(local: local)
        try await service.place(workspaceID: local.mirror, windowID: local.window)
        #expect(await local.order == [local.first, local.second, local.anchor, local.mirror])
        #expect(await local.creates == 1)
        #expect(await local.manual["external_id"] == .null)
        #expect(await !local.calls.contains("workspace.select"))
        #expect(await !local.calls.contains("workspace.group.focus"))
        try await service.place(workspaceID: local.mirror, windowID: local.window)
        #expect(await local.creates == 1)
    }
    @Test func explicitRecoveryAfterLostCreateUsesNativeIdentityWithoutAnotherGroup() async throws {
        let local = NativeGroupFixture(), service = NativeRemoteWorkspaceGroup(local: local)
        await local.loseCreateReceipt()
        await #expect(throws: BridgeError.self) { try await service.place(workspaceID: local.mirror, windowID: local.window) }
        #expect(await local.creates == 1)
        try await service.place(workspaceID: local.mirror, windowID: local.window)
        #expect(await local.creates == 1)
        #expect(await local.order == [local.first, local.second, local.anchor, local.mirror])
    }
    @Test func vanishedMirrorCannotCreateOrReorderAGroup() async throws {
        let local = NativeGroupFixture(), service = NativeRemoteWorkspaceGroup(local: local)
        await #expect(throws: BridgeError.self) {
            try await service.place(workspaceID: "77777777-7777-7777-7777-777777777777", windowID: local.window)
        }
        #expect(await local.creates == 0)
        #expect(await !local.calls.contains("workspace.reorder_many"))
    }
}
