//
//  FlightLog.swift
//  connectflight (iOS)
//
//  Created by Brice Rosenzweig on 27/06/2021.
//

import Foundation

class FlightLog {
    let url : URL
    var name : String { return url.lastPathComponent }
    
    var description : String { return "<FlightLog:\(name)>" }
    
    var data : FlightData? = nil
    
    init(url : URL) {
        self.url = url
    }
    
    func parse() {
        guard let str = try? String(contentsOf: self.url, encoding: .utf8) else { return }
        let lines = str.split(whereSeparator: \.isNewline)

        if self.data == nil {
            self.data = FlightData()
        }
        self.data?.parseLines(lines: lines)
        
    }
    
    static public func search(in urls: [URL], completion : (_ : [FlightLog]) -> Void){
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            var error :NSError? = nil
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error){
                (dirurl) in
                let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey]
                guard let fileList = FileManager.default.enumerator(at: dirurl, includingPropertiesForKeys: keys) else {
                    return
                }
                var found : [FlightLog] = []
                
                for case let file as URL in fileList {
                    if file.isLogFile {
                        found.append(FlightLog(url: file))
                    }
                    if file.lastPathComponent == "data_log" && file.hasDirectoryPath {
                        self.search(in: [file]) {
                            logs in
                            found.append(contentsOf: logs)
                        }
                    }
                }
                completion(found)
            }
        }
    }

}

//MARK: - interpretation
extension FlightLog {
    
}
