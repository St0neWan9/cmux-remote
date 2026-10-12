import Foundation
import CmuxAgentChat
import CmuxRemoteCore

/// Reuses upstream call identities, then supplements image blocks omitted by its text projection.
struct TranscriptImageIndex {
    struct Result { let records: [TranscriptImageRecord]; let supplementalMessages: [ChatMessage] }
    func read(lines: [String], messages: [ChatMessage], agent: String) throws -> Result {
        var records: [TranscriptImageRecord] = []
        var supplemental: [ChatMessage] = []
        var calls: [String: ChatMessage] = [:]
        var recordedPaths: [String: Data] = [:]
        let known = Set(messages.map(\.id))
        for (seq, line) in lines.enumerated() {
            try Task.checkCancellation()
            guard let root = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)), root["isSidechain"].bool != true else { continue }
            if agent == "claude" {
                if root["type"].string == "assistant" {
                    let parsed = ClaudeTranscriptParser().parse(lines: [line], startingSeq: seq)
                    for (id, pending) in parsed.state.pendingToolUses {
                        if let message = pending.first, known.contains(message.id) { calls[id] = message }
                    }
                }
                guard root["type"].string == "user", root["isMeta"].bool != true else { continue }
                let blocks = root["message"]["content"].array ?? []
                for (slot, block) in blocks.enumerated() {
                    if block["type"].string == "tool_result", let id = block["tool_use_id"].string, let tool = calls[id] {
                        for image in (block["content"].array ?? []).filter({ $0["type"].string == "image" }).prefix(4) {
                            if let data = imageData(image["source"]) {
                                records.append(TranscriptImageRecord(messageID: tool.id, name: "Image.jpg", source: .recorded(data)))
                                if case .toolUse(let value) = tool.kind, value.toolName == "Read", let path = value.referencedPaths?.first { recordedPaths[path] = data }
                            }
                        }
                    } else if block["type"].string == "image", let data = imageData(block["source"]) {
                        appendUserImage(data, seq: seq, slot: slot, identity: root["uuid"].string ?? "line-\(seq)", messages: messages, records: &records, supplemental: &supplemental)
                    }
                }
            } else if root["type"].string == "response_item", root["payload"]["type"].string == "message", root["payload"]["role"].string == "user" {
                for (slot, block) in (root["payload"]["content"].array ?? []).enumerated() where block["type"].string == "input_image" {
                    if let url = block["image_url"].string, let data = dataURL(url) { appendUserImage(data, seq: seq, slot: slot, identity: "line-\(seq)", messages: messages, records: &records, supplemental: &supplemental) }
                }
            }
            if records.count > 512 { records = Array(records.prefix(512)); break }
        }
        for message in messages {
            if case .toolUse(let tool) = message.kind {
                for path in (tool.referencedPaths ?? []).prefix(4) where ["png", "jpg", "jpeg"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) {
                    if !records.contains(where: { $0.messageID == message.id }) {
                        records.append(TranscriptImageRecord(messageID: message.id, name: String(URL(fileURLWithPath: path).lastPathComponent.prefix(255)), source: .projectPath(path)))
                    }
                }
            }
            if case .attachment(let value) = message.kind, value.media == .image, let path = value.hostPath {
                records.append(TranscriptImageRecord(messageID: message.id, name: String((value.displayName ?? URL(fileURLWithPath: path).lastPathComponent).prefix(255)), source: recordedPaths[path].map(TranscriptImageRecord.Source.recorded) ?? .projectPath(path)))
            }
        }
        var ids = Set<String>()
        records = records.filter { ids.insert($0.reference(generation: "deduplicate").id).inserted }
        return Result(records: Array(records.prefix(512)), supplementalMessages: supplemental)
    }
    private func imageData(_ source: JSONValue) -> Data? {
        guard source["type"].string == "base64", ["image/png", "image/jpeg"].contains(source["media_type"].string ?? ""),
              let encoded = source["data"].string, encoded.utf8.count <= 5_592_408,
              let bytes = Data(base64Encoded: encoded), !bytes.isEmpty, bytes.count <= 4_194_304 else { return nil }
        return bytes
    }
    private func dataURL(_ url: String) -> Data? {
        guard let separator = url.firstIndex(of: ","), ["data:image/png;base64", "data:image/jpeg;base64"].contains(String(url[..<separator])) else { return nil }
        return imageData(.object(["type": .string("base64"), "media_type": .string("image/jpeg"), "data": .string(String(url[url.index(after: separator)...]))]))
    }
    private func appendUserImage(_ data: Data, seq: Int, slot: Int, identity: String, messages: [ChatMessage], records: inout [TranscriptImageRecord], supplemental: inout [ChatMessage]) {
        let id = "remote-image:" + IdentityCryptography().digest(Data((identity + ":" + String(slot)).utf8))
        supplemental.append(ChatMessage(id: id, seq: seq, role: .user, timestamp: messages.first(where: { $0.seq == seq })?.timestamp ?? .distantPast, kind: .attachment(ChatAttachment(media: .image, displayName: "Image.jpg"))))
        records.append(TranscriptImageRecord(messageID: id, name: "Image.jpg", source: .recorded(data)))
    }
}
