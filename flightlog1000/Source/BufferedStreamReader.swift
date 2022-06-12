//
//  BufferedStreamReader.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 21/05/2022.
//

import Foundation
import OSLog

class BufferedStreamReader {
    private let inputStream : InputStream
    
    private var bufferIndex : Int
    private var bufferSize : Int
    private var bufferCapacity : Int
    private var buffer : [UInt8]
    
    var isAtEnd : Bool
    var readCount : Int
    
    init(inputStream : InputStream, capacity : Int = 1024 * 1024 ){
        self.inputStream = inputStream
        self.buffer = [UInt8](repeating: 0, count: capacity)
        
        self.bufferCapacity = capacity
        self.bufferIndex = 0
        self.bufferSize = 0
        self.readCount = 0
        
        self.isAtEnd = false
        
        if self.inputStream.streamStatus == .notOpen {
            self.inputStream.open()
        }
    }
    
    enum Byte {
        case endOfFile
        case char(UInt8)
        case error(Error)
    }
    
    func pop() -> Byte {
        guard !self.isAtEnd else { return Byte.endOfFile }
        
        var nextIndex = bufferIndex + 1
        if nextIndex >= self.bufferSize {
            let length = inputStream.read(&self.buffer, maxLength: self.bufferCapacity)
            if length == -1 {
                if let error = inputStream.streamError {
                    return Byte.error(error)
                }else{
                    return Byte.endOfFile
                }
            }
            if length == 0{
                self.bufferSize = 0
                self.bufferIndex = 0
                self.isAtEnd = true
                return Byte.endOfFile
            }
            self.bufferSize = length
            nextIndex = 0
        }
        
        readCount += 1
        bufferIndex = nextIndex
        
        return Byte.char(self.buffer[nextIndex])
    }
    
    func peek() -> UInt8? {
        guard !self.isAtEnd else { return nil }
        
        var nextIndex = bufferIndex + 1
        if nextIndex >= self.bufferSize {
            let length = inputStream.read(&self.buffer, maxLength: self.bufferCapacity)
            if length == 0{
                self.bufferSize = 0
                self.bufferIndex = 0
                self.isAtEnd = true
                return nil
            }
            nextIndex = 0
        }
        
        readCount += 1
        bufferIndex = nextIndex
        
        return self.buffer[nextIndex]

    }
}
