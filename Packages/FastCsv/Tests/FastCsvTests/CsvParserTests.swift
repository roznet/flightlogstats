import XCTest
@testable import FastCsv

final class CsvParserTests: XCTestCase {

    private class Collector : CsvInterpreter {
        var maxLineCount : Int? = nil
        var rows : [CsvRow] = []
        func start() {}
        func process(row : CsvRow, readCount : Int, lineCount : Int) { self.rows.append(row) }
        func finished() {}
    }

    private func rows(_ string : String, chunkSize : Int = 1024, maxLineCount : Int? = nil) throws -> [CsvRow] {
        let collector = Collector()
        collector.maxLineCount = maxLineCount
        try CsvParser.parse(inputStream: InputStream(data: Data(string.utf8)), interpreter: collector, chunkSize: chunkSize)
        return collector.rows
    }

    private func lines(_ string : String, chunkSize : Int = 1024) throws -> [[String]] {
        return try self.rows(string, chunkSize: chunkSize).map { $0.strings }
    }

    func testFieldsAndSpaces() throws {
        XCTAssertEqual(try lines("a,  b , c\n1,,3"), [["a", "b ", "c"], ["1", "", "3"]])
        XCTAssertEqual(try lines("a,\n"), [["a", ""]])
        XCTAssertEqual(try lines(""), [])
    }

    func testQuotes() throws {
        XCTAssertEqual(try lines("a,  \"b c\" ,d\n"), [["a", "b c", "d"]])
        XCTAssertEqual(try lines("\"a,b\",\"say \"\"hi\"\"\"\n"), [["a,b", "say \"hi\""]])
        XCTAssertEqual(try lines("\"a\nb\",c\n"), [["a\nb", "c"]])
        // a quote inside an unquoted field is kept
        XCTAssertEqual(try lines("key=\"a b\",c\n"), [["key=\"a b\"", "c"]])
    }

    func testLineEndings() throws {
        XCTAssertEqual(try lines("a,b\r1,\"x y\"\r"), [["a", "b"], ["1", "x y"]])
        XCTAssertEqual(try lines("a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(try lines("a\n\nb\n"), [["a"], [""], ["b"]])
    }

    func testChunkBoundaries() throws {
        let string = "a, \"b c\",d\r\n1,2.5,\"x\"\"y\"\r3,4,5\n"
        let expected = try lines(string)
        for chunkSize in 1...8 {
            XCTAssertEqual(try lines(string, chunkSize: chunkSize), expected, "chunk \(chunkSize)")
        }
    }

    func testMaxLineCount() throws {
        XCTAssertEqual(try rows("a\nb\nc\n", chunkSize: 2, maxLineCount: 2).map { $0.strings }, [["a"], ["b"]])
    }

    func testKeptRowIsStable() throws {
        let rows = try self.rows("a,b\nc,d\n")
        XCTAssertEqual(rows.map { $0.strings }, [["a", "b"], ["c", "d"]])
    }

    func testDoubles() throws {
        let values = ["1", "-2.5", "0.1", "1e3", "+4", "nan", "inf", "", " 1", "1 ", "1.2.3", "-", ".", ".5", "5.",
                      "12345678901234567890", "9007199254740993", "0.1234567890123456789012345", "abc", "-0.0"]
        let row = try self.rows(values.map { "\"\($0)\"" }.joined(separator: ","))[0]
        XCTAssertEqual(row.count, values.count)
        var bulk : [Double] = []
        row.doubles(at: Array(0..<row.count), into: &bulk)
        for (index, string) in values.enumerated() {
            let expected = Double(string)
            let got = row.double(at: index)
            XCTAssertEqual(got?.bitPattern, expected?.bitPattern, "'\(string)'")
            if let expected = expected, !expected.isNaN {
                XCTAssertEqual(bulk[index].bitPattern, expected.bitPattern, "'\(string)'")
            }else{
                XCTAssertTrue(bulk[index].isNaN, "'\(string)'")
            }
        }
    }

    /// The fast path must round exactly like Double(String)
    func testRandomDecimals() throws {
        var generator = SystemRandomNumberGenerator()
        var strings : [String] = []
        for _ in 0..<20000 {
            let digits = Int.random(in: 1...18, using: &generator)
            var string = Int.random(in: 0...1, using: &generator) == 0 ? "" : "-"
            for _ in 0..<digits {
                string.append(String(Int.random(in: 0...9, using: &generator)))
            }
            let dot = Int.random(in: 0...digits, using: &generator)
            if dot < digits {
                string.insert(".", at: string.index(string.endIndex, offsetBy: -(digits - dot)))
            }
            strings.append(string)
        }
        let row = try self.rows(strings.joined(separator: ","))[0]
        for (index, string) in strings.enumerated() {
            XCTAssertEqual(row.double(at: index)?.bitPattern, Double(string)?.bitPattern, string)
        }
    }
}
