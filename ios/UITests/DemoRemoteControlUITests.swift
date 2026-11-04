import XCTest

/// Local-only driver for recording the website demo. It reads one JSON command at a time from
/// CMUX_REMOTE_RC_DIR/cmd.json and writes the outcome to out.json, so a person can steer a real session.
@MainActor
final class DemoRemoteControlUITests: XCTestCase {
    func testRemoteControl() throws {
        guard let dir = ProcessInfo.processInfo.environment["CMUX_REMOTE_RC_DIR"], !dir.isEmpty else {
            throw XCTSkip("Recording driver only.")
        }
        let commandURL = URL(fileURLWithPath: dir).appendingPathComponent("cmd.json")
        let outURL = URL(fileURLWithPath: dir).appendingPathComponent("out.json")
        continueAfterFailure = true
        var app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        var lastSeq = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: commandURL))) as? [String: Any])?["seq"] as? Int ?? -1
        let deadline = Date().addingTimeInterval(3 * 60 * 60)
        func write(_ seq: Int, _ ok: Bool, _ detail: String) {
            let body: [String: Any] = ["seq": seq, "ok": ok, "detail": detail]
            if let data = try? JSONSerialization.data(withJSONObject: body) { try? data.write(to: outURL, options: .atomic) }
        }
        func element(_ command: [String: Any]) -> XCUIElement {
            if let id = command["id"] as? String { return app.descendants(matching: .any).matching(identifier: id).firstMatch }
            if let prefix = command["prefix"] as? String {
                return app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
            }
            let label = command["label"] as? String ?? ""
            let exact = command["exact"] as? Bool ?? false
            let predicate = exact ? NSPredicate(format: "label == %@", label) : NSPredicate(format: "label CONTAINS %@", label)
            return app.descendants(matching: .any).matching(predicate).element(boundBy: command["index"] as? Int ?? 0)
        }
        func element(_ command: [String: Any], type: XCUIElement.ElementType) -> XCUIElement {
            app.descendants(matching: type).matching(NSPredicate(format: "identifier BEGINSWITH %@", command["prefix"] as? String ?? "")).firstMatch
        }
        // Snapshots throw catchable errors; live element queries raise exceptions that end the test when a
        // refreshing list replaces a row between lookup and tap.
        func frame(_ command: [String: Any], timeout: Double) -> CGRect? {
            let end = Date().addingTimeInterval(timeout)
            repeat {
                if let root = try? app.snapshot(), let found = search(root, command) { return found }
                Thread.sleep(forTimeInterval: 0.25)
            } while Date() < end
            return nil
        }
        func search(_ node: XCUIElementSnapshot, _ command: [String: Any]) -> CGRect? {
            var matches: [CGRect] = []
            func visit(_ n: XCUIElementSnapshot) {
                var hit = false
                if let id = command["id"] as? String { hit = n.identifier == id }
                else if let prefix = command["prefix"] as? String { hit = n.identifier.hasPrefix(prefix) }
                else if let label = command["label"] as? String {
                    hit = (command["exact"] as? Bool ?? false) ? n.label == label : n.label.contains(label)
                }
                if hit, !n.frame.isEmpty { matches.append(n.frame) }
                n.children.forEach(visit)
            }
            visit(node)
            let index = command["index"] as? Int ?? 0
            return index < matches.count ? matches[index] : nil
        }
        func tap(_ rect: CGRect, _ command: [String: Any]) {
            let dx = command["dx"] as? Double ?? 0.5, dy = command["dy"] as? Double ?? 0.5
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: rect.minX + rect.width * dx, dy: rect.minY + rect.height * dy)).tap()
        }
        while Date() < deadline {
            guard let data = try? Data(contentsOf: commandURL),
                  let command = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let seq = command["seq"] as? Int, seq != lastSeq else {
                Thread.sleep(forTimeInterval: 0.15); continue
            }
            lastSeq = seq
            let op = command["op"] as? String ?? ""
            let timeout = command["timeout"] as? Double ?? 10
            switch op {
            case "launch":
                app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
                for (key, value) in command["env"] as? [String: String] ?? [:] { app.launchEnvironment[key] = value }
                app.launchArguments = ["-AppleLanguages", "(\(command["lang"] as? String ?? "zh-Hans"))",
                                       "-AppleLocale", command["locale"] as? String ?? "zh_CN"]
                app.launch()
                write(seq, true, "launched")
            case "terminate":
                app.terminate(); write(seq, true, "terminated")
            case "tap":
                if let rect = frame(command, timeout: timeout) { tap(rect, command); write(seq, true, "\(rect)") }
                else { write(seq, false, "missing") }
            case "tapPoint":
                let x = command["x"] as? Double ?? 0.5, y = command["y"] as? Double ?? 0.5
                app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap(); write(seq, true, "tapped")
            case "type":
                if command["focus"] as? Bool ?? true {
                    guard let rect = frame(command, timeout: timeout) else { write(seq, false, "missing"); continue }
                    tap(rect, command); Thread.sleep(forTimeInterval: 0.6)
                }
                app.typeText(command["text"] as? String ?? "")
                write(seq, true, "typed")
            case "swipe":
                let target: XCUIElement = app
                let velocity = XCUIGestureVelocity(rawValue: command["velocity"] as? Double ?? 600)
                switch command["dir"] as? String ?? "up" {
                case "down": target.swipeDown(velocity: velocity)
                case "left": target.swipeLeft(velocity: velocity)
                case "right": target.swipeRight(velocity: velocity)
                default: target.swipeUp(velocity: velocity)
                }
                write(seq, true, "swiped")
            case "drag":
                // A slow, visible scroll: press at one normalized point and move to another.
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: command["x"] as? Double ?? 0.5, dy: command["y1"] as? Double ?? 0.7))
                let to = app.coordinate(withNormalizedOffset: CGVector(dx: command["x"] as? Double ?? 0.5, dy: command["y2"] as? Double ?? 0.3))
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: XCUIGestureVelocity(rawValue: command["velocity"] as? Double ?? 400), thenHoldForDuration: 0.1)
                write(seq, true, "dragged")
            case "wait":
                write(seq, frame(command, timeout: timeout) != nil, "waited")
            case "tree":
                if let root = try? app.snapshot() {
                    var lines: [String] = []
                    func dump(_ n: XCUIElementSnapshot, _ depth: Int) {
                        if !n.identifier.isEmpty || !n.label.isEmpty {
                            lines.append(String(repeating: " ", count: depth) + "\(n.elementType.rawValue) id=\(n.identifier) label=\(n.label.prefix(80)) frame=\(n.frame)")
                        }
                        n.children.forEach { dump($0, depth + 1) }
                    }
                    dump(root, 0); write(seq, true, lines.joined(separator: "\n"))
                } else { write(seq, false, "no snapshot") }
            case "stop":
                write(seq, true, "stopped"); return
            default:
                write(seq, false, "unknown op \(op)")
            }
        }
    }
}
