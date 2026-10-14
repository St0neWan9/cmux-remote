import Testing
import CmuxRemoteCore

@Suite struct MarkdownTableTests {
    @Test func aHeaderDelimiterAndRowsBecomeATable() throws {
        let table = try #require(MarkdownTable(lines: ["| 项目 | 本月合计 |", "|---|---:|", "| Worker 请求 | 110 次 |", "| 存储 | 可以忽略 |"]))
        #expect(table.header == ["项目", "本月合计"])
        #expect(table.alignments == [.leading, .trailing])
        #expect(table.rows == [["Worker 请求", "110 次"], ["存储", "可以忽略"]])
    }
    @Test func outerPipesAreOptionalAndShortRowsArePadded() throws {
        let table = try #require(MarkdownTable(lines: ["a | b | c", ":-: | --- | :--", "1 | 2"]))
        #expect(table.alignments == [.center, .leading, .leading])
        #expect(table.rows == [["1", "2", ""]])
    }
    @Test func pipesInsideCodeOrEscapedStayInTheirCell() throws {
        let table = try #require(MarkdownTable(lines: ["| 命令 | 说明 |", "|---|---|", "| `a | b` | x \\| y |"]))
        #expect(table.rows == [["`a | b`", "x | y"]])
    }
    @Test func proseWithAPipeIsNotATable() {
        #expect(MarkdownTable(lines: ["这一行有 | 竖线", "但下一行不是分隔行"]) == nil)
        #expect(MarkdownTable(lines: ["| a | b |", "|---|"]) == nil)
    }
}
