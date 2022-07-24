//
//  FlightLegsDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 11/05/2022.
//

import Foundation
import UIKit
import OSLog
import RZUtils

class FlightLegsDataSource : NSObject, UICollectionViewDataSource, UICollectionViewDelegate, TableCollectionDelegate {
        
    typealias Field = FlightLogFile.Field
    typealias LegInfo = FlightLeg.LegInfo
    
    let legs : [FlightLeg]
    let fields : [Field]
    let fixedColumnsInfo : [LegInfo]
    let displayContext : DisplayContext
    
    private var attributedCells : [NSAttributedString] = []

    var frozenColumns : Int { return self.fixedColumnsInfo.count }
    var frozenRows : Int = 1
    
    init(legs : [FlightLeg], displayContext : DisplayContext = DisplayContext()){
        self.legs = legs
        
        var fields : Set<Field> = []
        for leg in legs {
            fields.formUnion(leg.fields)
        }
        self.fields = Array(fields).sorted {
            $0.order < $1.order
        }

        // should be sorted
        self.displayContext = displayContext
        self.fixedColumnsInfo = [.end_time,.waypoint]
        
    }
    
    //MARK: - delegate
        
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func formattedValueFor(field : Field, row : Int) -> String {
        guard let leg = self.legs[safe: row],
              let value = leg.valueStats(field: field)
        else {
            // empty string if missing for a blank in the table
            return ""
        }
        
        return field.format(valueStats: value, context: self.displayContext)
    }
    
    
    func prepare() {
        self.attributedCells  = []
        
        if let first = legs.first {
            // col 0 = time since start
            // col 1 = leg waypoints

            let reference = first.timeRange.start
            
            // first headers
            for title in self.fixedColumnsInfo {
                let titleAttributed = NSAttributedString(string: title.description, attributes: self.titleAttributes)
                self.attributedCells.append(titleAttributed)
            }

            for field in fields {
                let fieldAttributed = NSAttributedString(string: field.description, attributes: self.titleAttributes)
                self.attributedCells.append(fieldAttributed)
            }
            
            
            for (row,leg) in legs.enumerated() {
                for info in self.fixedColumnsInfo {
                    let fixedAttributed = NSAttributedString(string: leg.format(which: info, displayContext: self.displayContext, reference: reference), attributes: self.titleAttributes)
                    self.attributedCells.append(fixedAttributed)
                }
                for field in fields {
                    let fieldAttributed = NSAttributedString(string: self.formattedValueFor(field: field, row: row), attributes: self.cellAttributes)
                    self.attributedCells.append(fieldAttributed)
                }
            }
        }
    }
    
    func attributedString(at indexPath : IndexPath) -> NSAttributedString {
        let index = indexPath.section * (fields.count+fixedColumnsInfo.count) + indexPath.item
        return self.attributedCells[index]
    }
    
    func size(at indexPath: IndexPath) -> CGSize {
        return self.attributedString(at: indexPath).size()
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
            tableCell.label.attributedText = self.attributedString(at: indexPath)
            
            if indexPath.section < self.frozenRows || indexPath.item < self.frozenColumns{
                tableCell.backgroundColor = UIColor.systemBrown
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
