//
//  CsvParser.swift
//  FastCsv
//
//  Created by Brice Rosenzweig on 17/12/2022.
//

import Foundation

public protocol CsvInterpreter {
    // optional count of line to read, to only process part of the file
    var maxLineCount : Int? { get }

    func start()
    /// `row` views the parser's buffer: read it during the call, keeping it copies the buffer
    func process(row : CsvRow, readCount : Int, lineCount : Int)
    func finished()
}

/// One line of the file. Fields are stored as bytes and only converted when asked,
/// so a numeric column never becomes a String.
///
/// Nothing here is `@inlinable` on purpose: the calls run in this module, optimised
/// even when the caller is a Debug build.
public struct CsvRow {
    // each field is followed by a 0, so strtod reads it in place
    let bytes : [UInt8]
    // index in bytes of the 0 ending each field
    let ends : [Int]

    public var count : Int { return ends.count }

    private func start(_ index : Int) -> Int {
        return index == 0 ? 0 : ends[index - 1] + 1
    }

    public subscript(index : Int) -> String {
        return String(validating: bytes[start(index)..<ends[index]], as: UTF8.self) ?? ""
    }

    public var strings : [String] {
        return (0..<count).map { self[$0] }
    }

    public func isEmpty(at index : Int) -> Bool {
        return start(index) == ends[index]
    }

    /// Same result as `Double(self[index])`: nil if empty, leading space or not
    /// entirely a number
    public func double(at index : Int) -> Double? {
        return bytes.withUnsafeBufferPointer { buffer in
            Self.double(buffer, from: start(index), to: ends[index])
        }
    }

    /// Appends the double of each column to `values`, nan when not a number
    public func doubles(at columns : [Int], into values : inout [Double]) {
        bytes.withUnsafeBufferPointer { buffer in
            for index in columns {
                values.append(Self.double(buffer, from: start(index), to: ends[index]) ?? .nan)
            }
        }
    }

    private static let powersOfTen : [Double] = (0...22).map { pow(10.0, Double($0)) }

    private static func double(_ buffer : UnsafeBufferPointer<UInt8>, from : Int, to : Int) -> Double? {
        guard to > from else { return nil }

        // Exact fast path (Clinger) for plain decimals, [-]digits[.digits]: when the
        // digits make an integer up to 2^53 and there are at most 22 decimals, both
        // mantissa and 10^decimals are exact doubles and one division rounds correctly,
        // so the result is the same as strtod.
        var position = from
        let negative = buffer[position] == UInt8(ascii: "-")
        if negative {
            position += 1
        }
        var mantissa : UInt64 = 0
        var digits = 0
        var decimals = 0
        var seenDot = false
        var fastPath = true
        while position < to {
            let char = buffer[position]
            if char >= UInt8(ascii: "0") && char <= UInt8(ascii: "9") {
                // stays below 2^64: mantissa was at most 2^53
                mantissa = mantissa * 10 + UInt64(char - UInt8(ascii: "0"))
                if mantissa > 1 << 53 {
                    fastPath = false
                    break
                }
                digits += 1
                if seenDot {
                    decimals += 1
                }
            }else if char == UInt8(ascii: ".") && !seenDot {
                seenDot = true
            }else{
                fastPath = false
                break
            }
            position += 1
        }
        if fastPath && digits > 0 && decimals < powersOfTen.count {
            let value = Double(mantissa) / powersOfTen[decimals]
            return negative ? -value : value
        }
        // exponent, sign, inf, nan, long mantissa or not a number
        return Double(String(decoding: UnsafeBufferPointer(rebasing: buffer[from..<to]), as: UTF8.self))
    }
}

public enum CsvParser {
    // Specialised csvParser that ignores spaces at beginning of a field

    private enum State {
        case beginningOfLine
        case maybeEndOfLine
        case endOfLine

        case maybeInField   // while we only see spaces we ignore, but could be inField
        case inField  // we are collecting char for field
        case endOfField  // end of field

        case inQuotedField
        case maybeEndOfQuotedField
    }

    private enum Scalar {
        static let carriageReturn = UInt8(ascii: "\r")
        static let lineFeed = UInt8(ascii: "\n")
        static let doubleQuote = UInt8(ascii: "\"")
        static let comma = UInt8(ascii: ",")
        static let space = UInt8(ascii: " ")
    }

    public enum ParseError : Error {
        case invalidStateForComma
        case invalidStateForNewLine
        case invalidStateForQuote
        case invalidStateForOtherChar
    }

    /// Reads the stream in chunks of `chunkSize` bytes, calls the interpreter once per line.
    /// `\n`, `\r\n` and a lone `\r` end a line; a trailing line end does not add an empty line.
    public static func parse(inputStream : InputStream, interpreter : CsvInterpreter, chunkSize : Int = 1024 * 1024) throws {
        if inputStream.streamStatus == .notOpen {
            inputStream.open()
        }
        interpreter.start()

        var state : State = .beginningOfLine
        var bytes : [UInt8] = []
        var ends : [Int] = []
        var lineCount : Int = 0
        var readCount : Int = 0
        // no closures in the loop: captured vars are boxed on the heap, slow per byte
        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { chunk.deallocate() }
        var stop = false

        reading: while true {
            let length = inputStream.read(chunk, maxLength: chunkSize)
            if length < 0, let error = inputStream.streamError {
                throw error
            }
            if length <= 0 {
                break
            }
            do {
                for position in 0..<length {
                    let char = chunk[position]

                    if state == .endOfLine {
                        state = .beginningOfLine
                    }
                    // a \r already ended the line: unless \n follows (\r\n), it was a lone \r
                    if state == .maybeEndOfLine && char != Scalar.lineFeed {
                        state = .beginningOfLine
                    }

                    switch char {
                    case Scalar.comma:
                        switch state {
                        case .beginningOfLine, .inField, .maybeInField, .maybeEndOfQuotedField, .endOfField:
                            state = .endOfField
                        case .inQuotedField:
                            bytes.append(char)
                        default:
                            throw ParseError.invalidStateForComma
                        }
                    case Scalar.carriageReturn:
                        switch state {
                        case .endOfField, .beginningOfLine, .inField, .maybeInField, .maybeEndOfQuotedField:
                            state = .maybeEndOfLine
                        case .inQuotedField:
                            bytes.append(char)
                        default:
                            throw ParseError.invalidStateForNewLine
                        }
                    case Scalar.lineFeed:
                        switch state {
                        case .endOfField, .beginningOfLine, .inField, .maybeInField, .maybeEndOfQuotedField:
                            state = .endOfLine
                        case .inQuotedField:
                            bytes.append(char)
                        case .maybeEndOfLine:
                            // \n of a \r\n: the \r ended the line
                            state = .beginningOfLine
                        default:
                            throw ParseError.invalidStateForNewLine
                        }
                    case Scalar.space:
                        switch state {
                        case .inField, .inQuotedField:
                            bytes.append(char)
                        case .maybeEndOfQuotedField:
                            // spaces after the closing quote are ignored
                            break
                        default:
                            state = .maybeInField
                        }
                    case Scalar.doubleQuote:
                        switch state {
                        case .beginningOfLine, .endOfField, .maybeInField:
                            state = .inQuotedField
                        case .maybeEndOfQuotedField:
                            // double double quote, to escape double quote
                            bytes.append(char)
                            state = .inQuotedField
                        case .inField:
                            bytes.append(char)
                        case .inQuotedField:
                            // first one
                            state = .maybeEndOfQuotedField
                        default:
                            throw ParseError.invalidStateForQuote
                        }
                    default:
                        switch state {
                        case .beginningOfLine, .endOfField, .maybeInField:
                            bytes.append(char)
                            state = .inField
                        case .maybeEndOfQuotedField:
                            break
                        case .inField, .inQuotedField:
                            bytes.append(char)
                        default:
                            throw ParseError.invalidStateForOtherChar
                        }
                    }

                    switch state {
                    case .endOfField:
                        ends.append(bytes.count)
                        bytes.append(0)
                    case .endOfLine, .maybeEndOfLine:
                        ends.append(bytes.count)
                        bytes.append(0)
                        interpreter.process(row: CsvRow(bytes: bytes, ends: ends), readCount: readCount + position + 1, lineCount: lineCount)
                        bytes.removeAll(keepingCapacity: true)
                        ends.removeAll(keepingCapacity: true)
                        lineCount += 1
                        if let maxLineCount = interpreter.maxLineCount, lineCount >= maxLineCount {
                            stop = true
                        }
                    default:
                        break
                    }
                    if stop {
                        break
                    }
                }
            }
            readCount += length
            if let maxLineCount = interpreter.maxLineCount, lineCount >= maxLineCount {
                interpreter.finished()
                return
            }
        }
        // last line without a line end
        switch state {
        case .beginningOfLine, .endOfLine, .maybeEndOfLine:
            break
        default:
            ends.append(bytes.count)
            bytes.append(0)
            interpreter.process(row: CsvRow(bytes: bytes, ends: ends), readCount: readCount, lineCount: lineCount)
        }
        interpreter.finished()
    }
}
