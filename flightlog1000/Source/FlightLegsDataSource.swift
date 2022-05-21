//
//  FlightLegsDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 11/05/2022.
//

import Foundation
import UIKit
import OSLog

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
    
    var contentSize : CGSize = CGSize.zero
    
    var frozenColumns : Int { return self.fixedColumnsInfo.count }
    var frozenRows : Int = 1
    
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
        self.fixedColumnsInfo = [.end_time,.waypoint_from,.waypoint_to]
        
    }
    
    //MARK: - delegate
    func size(at: IndexPath) -> CGSize {
        guard legs.count > 0 else { return CGSize.zero }
        return CGSize(width: self.columnsWidth[at.item], height: self.rowsHeight[at.section])
    }
    
    func prepare() {
        self.computeGeometry()
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
        
        self.contentSize = CGSize.zero
        self.attributedCells  = []
        self.cellSizes  = []
        self.columnsWidth  = []
        self.rowsHeight = []
        let marginMultiplier = CGSize(width: 1.2, height: 1.2)
        
        if let first = legs.first {
            // col 0 = time since start
            // col 1 = leg waypoints

            let reference = first.timeRange.start
            
            // first headers
            var rowHeight : CGFloat = 0.0
            for title in self.fixedColumnsInfo {
                let titleAttributed = NSAttributedString(string: title.description, attributes: self.titleAttributes)
                let titleSize = titleAttributed.size()
                self.attributedCells.append(titleAttributed)
                self.cellSizes.append(titleSize)
                self.columnsWidth.append(titleSize.width * marginMultiplier.width)
                rowHeight  = max(rowHeight, titleSize.height * marginMultiplier.height)
            }

            for field in fields {
                let fieldAttributed = NSAttributedString(string: field.description, attributes: self.titleAttributes)
                let fieldSize = fieldAttributed.size()
                self.attributedCells.append(fieldAttributed)
                self.cellSizes.append(fieldSize)
                self.columnsWidth.append(fieldSize.width * marginMultiplier.width)
                rowHeight = max(rowHeight, fieldSize.height * marginMultiplier.height)
            }
            self.rowsHeight.append(rowHeight)
            self.contentSize.height += rowHeight
            
            var row = 0
            for leg in legs {
                var idx = 0
                rowHeight = 0.0
                for info in self.fixedColumnsInfo {
                    let fixedAttributed = NSAttributedString(string: leg.format(which: info, displayContext: self.displayContext, reference: reference), attributes: self.titleAttributes)
                    let fixedSize = fixedAttributed.size()
                    self.attributedCells.append(fixedAttributed)
                    self.cellSizes.append(fixedSize)
                    self.columnsWidth[idx] = max(fixedSize.width*marginMultiplier.width, self.columnsWidth[idx])
                    rowHeight = max(rowHeight, fixedSize.height*marginMultiplier.height)
                    idx += 1
                }
                for field in fields {
                    let fieldAttributed = NSAttributedString(string: self.formattedValueFor(field: field, row: row), attributes: self.cellAttributes)
                    let fieldSize = fieldAttributed.size()
                    self.attributedCells.append(fieldAttributed)
                    self.cellSizes.append(fieldSize)
                    self.columnsWidth[idx] = max(self.columnsWidth[idx], fieldSize.width*marginMultiplier.width)
                    rowHeight = max(rowHeight, fieldSize.height*marginMultiplier.height)
                    idx += 1
                }
                self.rowsHeight.append(rowHeight)
                self.contentSize.height += rowHeight
                row += 1
            }
            
            self.contentSize.width = self.columnsWidth.reduce(0.0, +)
        }
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard legs.count > 0 else { return 0 }
        return legs.count + 1 /* for header */
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard legs.count > 0 else { return 0 }
        return self.fixedColumnsInfo.count + self.fields.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TableCollectionViewCell", for: indexPath)
        if let tableCell = cell as? TableCollectionViewCell {
            let index = indexPath.section * self.columnsWidth.count + indexPath.item
            tableCell.label.attributedText = self.attributedCells[index]
            
            if indexPath.section < self.frozenRows || indexPath.item < self.frozenColumns{
                tableCell.backgroundColor = UIColor.systemCyan
            }else{
                if indexPath.section % 2 == 0{
                    tableCell.backgroundColor = UIColor.systemBackground
                }else{
                    tableCell.backgroundColor = UIColor.systemGroupedBackground
                }
            }
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.app.info("Selected \(indexPath)")
    }
}
