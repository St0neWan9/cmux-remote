import XCTest
import UIKit
import CmuxRemoteCore
@testable import CmuxRemote

final class MarkdownTableMetricsTests: XCTestCase {
    private let body = UIFont.systemFont(ofSize: 15), header = UIFont.systemFont(ofSize: 15, weight: .semibold)
    private func metrics(_ lines: [String]) throws -> MarkdownTableMetrics {
        MarkdownTableMetrics(table: try XCTUnwrap(MarkdownTable(lines: lines)), body: body, header: header)
    }
    func testAShortTableSpansTheMessageWithoutWrapping() throws {
        let table = try metrics(["| 项目 | 结果 |", "|---|---|", "| 测试 | 通过 |"])
        let widths = table.widths(available: 340, gap: 16)
        XCTAssertEqual(widths.reduce(0, +) + 16, 340, accuracy: 0.5)
        XCTAssertTrue(zip(widths, table.natural).allSatisfy { $0 >= $1 })
    }
    func testOnlyTheWidestColumnWrapsWhenTheTableIsTooWide() throws {
        let table = try metrics(["| 保留的本地分支 | 状态 | 保留原因 |", "|---|---|---|",
                                 "| `claude/multi-host-relay-directory` | 当前开发分支 | 有进行中的改动 |",
                                 "| `claude/link-input-budget` | 尚未合入 main | 保留未合并提交 |"])
        // About a phone's message width: the code column wraps at its hyphens and the short columns stay on one line.
        let widths = table.widths(available: 370, gap: 16)
        XCTAssertEqual(widths.reduce(0, +) + 32, 370, accuracy: 0.5)
        XCTAssertLessThan(widths[0], table.natural[0])
        XCTAssertEqual(widths[1], table.natural[1], accuracy: 0.5)
        XCTAssertEqual(widths[2], table.natural[2], accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(widths[0], table.minimum[0])
    }
    func testIdentifiersAndPathsNeverSplitInsideButHyphensAndCJKDo() throws {
        let code = try metrics(["| a |", "|---|", "| `requests_per_worker_instance` |"])
        XCTAssertEqual(code.minimum[0], code.natural[0], accuracy: 0.5)
        let hyphenated = try metrics(["| a |", "|---|", "| `claude/link-input-budget` |"])
        XCTAssertLessThan(hyphenated.minimum[0], hyphenated.natural[0] * 0.6)
        let chinese = try metrics(["| a |", "|---|", "| 保留未合并提交 |"])
        XCTAssertLessThan(chinese.minimum[0], chinese.natural[0] / 4)
    }
    func testATableThatCannotWrapNarrowEnoughKeepsItsMinimumAndScrolls() throws {
        let table = try metrics(["| 指标 | 周一 | 周二 | 周三 | 周四 | 周五 |", "|---|---:|---:|---:|---:|---:|",
                                 "| `requests_per_worker_instance` | 1,204,331 | 1,198,442 | 1,302,118 | 1,250,000 | 1,410,229 |"])
        let widths = table.widths(available: 340, gap: 16)
        XCTAssertEqual(widths, table.minimum)
        XCTAssertGreaterThan(widths.reduce(0, +) + 80, 340)
    }
}
