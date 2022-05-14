//
//  FlightLegsDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 11/05/2022.
//

import Foundation
import UIKit

class FlightLegsDataSource : NSObject, UICollectionViewDataSource, UICollectionViewDelegate, TableCollectionSizeDelegate {
    typealias Field = FlightLogFile.Field
    typealias LegInfo = FlightLeg.LegInfo
    
    let legs : [FlightLeg]
    let fields : [Field]
    let fixedColumnsInfo : [LegInfo]
    let displayContext : DisplayContext
    
    var attributedCells : [NSAttributedString] = []
    var cellSizes : [CGSize] = []
    var columnsWidth : [CGFloat] = []
    var rowsHeight : [CGFloat] = []
    var totalSize : CGSize = CGSize.zero
    
    
    init(legs : [FlightLeg], displayContext : DisplayContext = DisplayContext()){
        self.legs = legs

        
        var fields : Set<Field> = []
        for leg in legs {
            fields.formUnion(leg.data.keys)
        }
        self.fields = Array(fields).sorted {
            $0.order < $1.order
        }

        // should be sorted
        self.displayContext = displayContext
        self.fixedColumnsInfo = [.end_time,.route]
        
    }
    
    func size(at: IndexPath) -> CGSize {
        return CGSize.zero
    }
    
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func formattedValueFor(field : Field, row : Int) -> String {
        guard let leg = self.legs[safe: row],
              let value = leg.data[field]
        else {
            // empty string if missing for a blank in the table
            return ""
        }
        
        return field.format(valueStats: value, context: self.displayContext)
    }
    
    func computeGeometry() {
        
        self.totalSize = CGSize.zero
        self.attributedCells  = []
        self.cellSizes  = []
        self.columnsWidth  = []
        self.rowsHeight = []
        
        if let first = legs.first {
            // col 0 = time since start
            // col 1 = leg waypoints

            let since = first.timeRange.start
            
            // first headers
            var rowHeight : CGFloat = 0.0
            for title in self.fixedColumnsInfo {
                let titleAttributed = NSAttributedString(string: title.description, attributes: self.titleAttributes)
                let titleSize = titleAttributed.size()
                self.attributedCells.append(titleAttributed)
                self.cellSizes.append(titleSize)
                self.columnsWidth.append(titleSize.width)
                rowHeight  = max(rowHeight, titleSize.height)
            }

            for field in fields {
                let fieldAttributed = NSAttributedString(string: field.description, attributes: self.titleAttributes)
                let fieldSize = fieldAttributed.size()
                self.attributedCells.append(fieldAttributed)
                self.cellSizes.append(fieldSize)
                self.columnsWidth.append(fieldSize.width)
                rowHeight = max(rowHeight, fieldSize.height)
            }
            self.rowsHeight.append(rowHeight)
            self.totalSize.height += rowHeight
            
            var row = 0
            for leg in legs {
                var idx = 0
                rowHeight = 0.0
                for info in self.fixedColumnsInfo {
                    let fixedAttributed = NSAttributedString(string: leg.format(which: info, displayContext: self.displayContext), attributes: self.titleAttributes)
                    let fixedSize = fixedAttributed.size()
                    self.attributedCells.append(fixedAttributed)
                    self.cellSizes.append(fixedSize)
                    self.columnsWidth[idx] = max(fixedSize.width, self.columnsWidth[idx])
                    rowHeight = max(rowHeight, fixedSize.height)
                    idx += 1
                }
                for field in fields {
                    let fieldAttributed = NSAttributedString(string: self.formattedValueFor(field: field, row: row), attributes: self.cellAttributes)
                    let fieldSize = fieldAttributed.size()
                    self.attributedCells.append(fieldAttributed)
                    self.cellSizes.append(fieldSize)
                    self.columnsWidth[idx] = max(self.columnsWidth[idx], fieldSize.width)
                    rowHeight = max(rowHeight, fieldSize.height)
                    idx += 1
                }
                self.rowsHeight.append(rowHeight)
                self.totalSize.height += rowHeight
                row += 1
            }
            
            self.totalSize.width = self.columnsWidth.reduce(0.0, +)
        }
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return legs.count
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 2 /*time+waypoint*/
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return UICollectionViewCell()
    }
    
}
