//
//  URLBookMark.swift
//  FlightLogStats
//
//  Created by Brice Rosenzweig on 31/12/2023.
//

import Foundation

extension [URL] {
    func bookmarks(options: NSURL.BookmarkCreationOptions = .minimalBookmark ) -> [Data] {
        self.compactMap {
           try? $0.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }
}

extension [Data] {
    func urls(options: URL.BookmarkResolutionOptions = .withoutUI) -> [URL] {
        self.compactMap {
            var stale : Bool = false
            let rv = try? URL(resolvingBookmarkData: $0, options: options, bookmarkDataIsStale: &stale)
            return rv
        }
    }
}
