//
//  CsvParser.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 17/12/2022.
//

import Foundation
import OSLog

protocol CsvInterpreter {
    // optional count of line to read, to only process part of the file
    var maxLineCount : Int? { get }
    
    func start()
    func process(line : [String], readCount : Int, lineCount : Int)
    func finished()
}


class CsvParser {
    // Specialised csvParser that ignores spaces at beginning of a field
    
    private enum State {
        case beginningOfDocument
        case endOfDocument
        
        case beginningOfLine
        case maybeEndOfLine
        case endOfLine
        
        case maybeInField   // while we only see spaces we ignore, but could be inField
        case inField  // we are collecting char for field
        case endOfField  // end of field

        case inQuotedField
        case maybeEndOfQuotedField
    }
    
    private struct CSVScalar  {
        static let CarriageReturn : UnicodeScalar = "\r"
        static let LineFeed : UnicodeScalar = "\n"
        static let DoubleQuote : UnicodeScalar = "\""
        static let Comma : UnicodeScalar = ","
        static let Space : UnicodeScalar = " "
    }
    
    enum ParseError : Error {
        case invalidStateForComma
        case invalidStateForNewLine
        case invalidStateForQuote
        case invalidStateForOtherChar
    }
    
    static func parse(bufferedStreamReader : BufferedStreamReader, interpreter : CsvInterpreter) throws {
        interpreter.start()
        
        var state : State = .beginningOfDocument
        
        var fieldBuffer : [UInt8] = []
        
        var line : [String] = []
        var lineCount : Int = 0
        
        while state != .endOfDocument {
            let byte = bufferedStreamReader.pop()
            switch byte {
            case .error(let error):
                throw error
            case .endOfFile:
                state = .endOfDocument
            case .char(let char):
                
                let scalar = UnicodeScalar(char)
                if state == .beginningOfDocument {
                    state = .beginningOfLine
                }
                
                if state == .endOfLine {
                    state = .beginningOfLine
                }
                
                switch scalar {
                case CSVScalar.Comma:
                    switch state {
                    case .beginningOfLine:
                        state = .endOfField
                    case .inField, .maybeInField:
                        state = .endOfField
                    case .inQuotedField:
                        fieldBuffer.append(char)
                    case .maybeEndOfQuotedField,.endOfField:
                        state = .endOfField
                    default:
                        throw ParseError.invalidStateForComma
                    }
                case CSVScalar.CarriageReturn:
                    switch state {
                    case .endOfField, .beginningOfLine, .inField, .maybeInField, .maybeEndOfQuotedField:
                        state = .maybeEndOfLine
                    case .inQuotedField:
                        fieldBuffer.append(char)
                    default:
                        throw ParseError.invalidStateForNewLine
                    }
                case CSVScalar.LineFeed:
                    switch state {
                    case .endOfField, .beginningOfLine, .inField, .maybeInField, .maybeEndOfQuotedField:
                        state = .endOfLine
                    case .inQuotedField:
                        fieldBuffer.append(char)
                    case .maybeEndOfLine:
                        state = .beginningOfLine
                    default:
                        throw ParseError.invalidStateForNewLine
                    }
                case CSVScalar.Space:
                    switch state {
                    case .inField:
                        fieldBuffer.append(char)
                    default:
                        state = .maybeInField
                    }
                case CSVScalar.DoubleQuote:
                    switch state {
                    case .beginningOfLine, .endOfField:
                        state = .inQuotedField
                    case .maybeEndOfQuotedField:
                        // double double quote, to escape double quote
                        fieldBuffer.append(char)
                        state = .inQuotedField
                    case .inField:
                        fieldBuffer.append(char)
                    case .inQuotedField:
                        // first one
                        state = .maybeEndOfQuotedField
                    default:
                        throw ParseError.invalidStateForQuote
                    }
                default:
                    switch state {
                    case .beginningOfLine, .endOfField:
                        fieldBuffer.append(char)
                        state = .inField
                    case .maybeEndOfQuotedField:
                        state = .maybeEndOfQuotedField
                    case .maybeInField:
                        // we had spaces so far but now field is starting
                        fieldBuffer.append(char)
                        state = .inField
                    case .inField, .inQuotedField:
                        fieldBuffer.append(char)
                    default:
                        throw ParseError.invalidStateForOtherChar
                    }
                }
            }
            if state == .endOfField || state == .endOfLine || state == .maybeEndOfLine || state == .endOfDocument {
                if let value = String(data: Data(fieldBuffer), encoding: .utf8) {
                    line.append(value)
                }else{
                    line.append("") // empty
                }
                fieldBuffer.removeAll(keepingCapacity: true)
                if state != .endOfField {
                    interpreter.process(line: line, readCount: bufferedStreamReader.readCount, lineCount: lineCount)
                    line.removeAll(keepingCapacity: true)
                    lineCount += 1
                    if let maxLinesCount = interpreter.maxLineCount, lineCount >= maxLinesCount {
                        // finish after maxLinesCount if defined
                        state = .endOfDocument
                    }
                }
            }
        }
        interpreter.finished()
    }
}
