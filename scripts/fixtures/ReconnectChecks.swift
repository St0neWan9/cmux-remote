import Foundation
import CmuxRemoteClient

/// The automatic redial pacing: a dropped working link is dialed at once, then retries back off.
enum ReconnectChecks {
    @MainActor static func run() async -> (count: Int, failures: [String]) {
        var count = 0, failures: [String] = []
        func check(_ condition: Bool, _ message: String) { count += 1; if !condition { failures.append(message) } }

        let standard = ReconnectSchedule()
        check(standard.pause == .seconds(2), "A Mac that never connected no longer waits the first pause before a retry")

        // A working link that drops cuts a long pause short and is redialed at once.
        let pauses: [Duration] = [.seconds(30), .milliseconds(40), .milliseconds(80), .milliseconds(120)]
        let schedule = ReconnectSchedule(pauses: pauses)
        let started = ContinuousClock.now
        let napping = Task { @MainActor in await schedule.wait() }
        await Task.yield()
        schedule.observe(host: "studio", from: nil, to: .connected)
        schedule.observe(host: "studio", from: .connected, to: .disconnected)
        let full = await napping.value
        check(!full && ContinuousClock.now - started < .seconds(5), "A dropped link waited out the pause instead of redialing at once")
        check(schedule.step(states: ["studio": .disconnected, "laptop": .connected], waited: full) == .redialDropped(["studio"]),
              "A dropped link was not redialed at once, or a working Mac was redialed with it")
        check(schedule.attempt == 1 && schedule.pause == pauses[1], "The immediate redial did not count as the first retry")

        // Still down: the next retries back off from the second pause.
        let secondFull = await schedule.wait()
        check(secondFull && schedule.step(states: ["studio": .disconnected], waited: secondFull) == .retryLost(attempt: 2, waited: pauses[1]),
              "A Mac still down after the immediate redial was not retried after the next pause")
        check(schedule.pause == pauses[2], "Retries after an immediate redial stopped backing off")
        check(schedule.step(states: ["studio": .connected], waited: true) == .idle && schedule.attempt == 0, "A recovered link kept the backoff")

        // A drop observed while that Mac is already dialing again starts no second dial.
        schedule.observe(host: "studio", from: .connected, to: .disconnected)
        check(schedule.step(states: ["studio": .connecting], waited: false) == .idle, "A dropped Mac already dialing was dialed twice")

        // A failed dial, or a first report of a Mac that is down, is not a drop: it waits out the pause.
        let failing = ReconnectSchedule(pauses: [.milliseconds(40)])
        failing.observe(host: "studio", from: .connecting, to: .disconnected)
        failing.observe(host: "laptop", from: nil, to: .disconnected)
        let failedFull = await failing.wait()
        check(failedFull, "A failed dial woke the retry early and could redial a dead path in a loop")
        check(failing.step(states: ["studio": .disconnected, "laptop": .disconnected], waited: failedFull) == .retryLost(attempt: 1, waited: .milliseconds(40)),
              "A Mac whose dial failed was not retried after the pause")
        check(failing.step(states: ["studio": .disconnected, "laptop": .connecting], waited: true) == .idle, "A retry started while another Mac was still dialing")
        // A dial in flight must not reset the backoff: otherwise a dead path stays at the shortest pause.
        check(failing.attempt == 1, "A Mac still dialing reset the backoff")

        // A drop seen while the loop was busy dialing is handled without another pause.
        let busy = ReconnectSchedule(pauses: [.seconds(30)])
        busy.observe(host: "studio", from: .connected, to: .disconnected)
        let busyFull = await busy.wait()
        check(!busyFull && busy.step(states: ["studio": .disconnected], waited: busyFull) == .redialDropped(["studio"]), "A drop seen during a dial waited a full pause")

        // The default pauses double from 2s to 256s and then stay at 256s.
        let doubling = ReconnectSchedule()
        var seen: [Duration] = []
        for _ in 0..<10 { seen.append(doubling.pause); _ = doubling.step(states: ["studio": .disconnected], waited: true) }
        check(seen == [2, 4, 8, 16, 32, 64, 128, 256, 256, 256].map { .seconds($0) }, "The retry pauses did not double up to 256s and hold there: \(seen)")

        // A Mac that stays down is never given up on, but only the first retries are shown.
        let endless = ReconnectSchedule(pauses: [.milliseconds(20)], visibleAttempts: 2)
        endless.observe(host: "studio", from: nil, to: .disconnected)
        var steps: [ReconnectSchedule.Step] = [], quiet: [Bool] = []
        for _ in 0..<6 {
            let full = await endless.wait()
            steps.append(endless.step(states: ["studio": .disconnected], waited: full)); quiet.append(endless.quiet)
        }
        check(steps == (1...6).map { .retryLost(attempt: $0, waited: .milliseconds(20)) }, "A Mac that stays down stopped being retried")
        check(quiet == [false, false, true, true, true, true], "Retries past the visible ones were still shown, or the first ones were hidden")
        // A person's retry (or a network change) starts over, shown again.
        endless.rearm()
        check(!endless.quiet && endless.step(states: ["studio": .disconnected], waited: true) == .retryLost(attempt: 1, waited: .milliseconds(20)),
              "Re-arming did not start the backoff over")
        // A Mac that comes back starts over too.
        check(endless.step(states: ["studio": .connected], waited: true) == .idle && endless.attempt == 0 && !endless.quiet, "A recovered Mac kept the quiet backoff")

        // The race loser's line is informational; real failures stay warnings.
        check(diagLinkLevel("dial lan cancelled after 2706ms: relay connected first") == .info, "A path that lost the dial race was logged as a warning")
        check(diagLinkLevel("dial relay cancelled after 41ms: lan connected first") == .info, "A relay that lost the dial race was logged as a warning")
        check(diagLinkLevel("dial lan failed 4001ms unreachable=true error=URLError(-1001 timedOut)") == .warning, "A failed LAN dial is no longer a warning")
        check(diagLinkLevel("heartbeat ping timeout after 10s error=URLError(-1001 timedOut)") == .warning, "A heartbeat timeout is no longer a warning")
        return (count, failures)
    }
}
