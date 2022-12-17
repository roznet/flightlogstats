//
//  TableDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 29/07/2022.
//

import Foundation

import UIKit
import OSLog
import RZUtils
import RZUtilsSwift

class TableDataSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, TableCollectionDelegate   {

    typealias IndexPathSelectedCallback = (_ : IndexPath?) -> Void
    
    enum CellHolder {
        case attributedString(NSAttributedString)
        case numberWithUnit(GCNumberWithUnit,[NSAttributedString.Key:Any]?)
        case measurement(Measurement<Dimension>,MeasurementFormatter,[NSAttributedString.Key:Any]?)
        case compoundMeasurement(Measurement<Dimension>,CompoundMeasurementFormatter<Dimension>,[NSAttributedString.Key:Any]?)
        
        init(string : String, attributes: [NSAttributedString.Key:Any]? = nil ) {
            self = .attributedString(NSAttributedString(string: string, attributes: attributes))
        }
        init(numberWithUnit : GCNumberWithUnit, attributes : [NSAttributedString.Key:Any]? = nil){
            self = .numberWithUnit(numberWithUnit, attributes)
        }
        init(measurement: Measurement<Dimension>, formatter : MeasurementFormatter, attributes : [NSAttributedString.Key:Any]? = nil){
            self = .measurement(measurement, formatter, attributes)
        }

        init(measurement: Measurement<Dimension>, compound : CompoundMeasurementFormatter<Dimension>, attributes : [NSAttributedString.Key:Any]? = nil){
            self = .compoundMeasurement(measurement, compound, attributes)
        }

    }
    
    var indexPathSelectedCallback : IndexPathSelectedCallback? = nil
    
    var cellHolders : [CellHolder] = []
    var geometries : [RZNumberWithUnitGeometry] = []
    
    var frozenColumns : Int
    var frozenRows : Int
    
    var columnsCount : Int
    var rowsCount : Int
    
    var selectedIndexPath : IndexPath? = nil
    
    var highlightedBackgroundRows : Set<Int> = []
    
    //               Total    Left   Right
    //    Start
    //    End
    //    Remaining

    init(rows : Int, columns : Int, frozenColumns : Int, frozenRows : Int) {
        self.rowsCount = rows
        self.columnsCount = columns
        self.frozenRows = frozenRows
        self.frozenColumns = frozenColumns
    }
    
    //MARK: - delegate
    
    // To override
    func attribute(at indexPath : IndexPath) -> [NSAttributedString.Key:Any] {
        if indexPath.section < self.frozenRows || indexPath.item < self.frozenColumns{
            return [.font:UIFont.boldSystemFont(ofSize: 14.0)]
        }else{
            return [.font:UIFont.systemFont(ofSize: 14.0)]
        }
    }
    
    var frozenColor : UIColor = UIColor.systemCyan
    var selectedColor : UIColor = UIColor.systemTeal
    var highlightedBackgroundColor : UIColor =  UIColor.systemCyan //UIColor.secondarySystemBackground
    
    func setBackgroundColor(for tableCell: UICollectionViewCell, itemAt indexPath : IndexPath) {
        if self.highlightedBackgroundRows.contains(indexPath.section){
            tableCell.backgroundColor = self.highlightedBackgroundColor
        }else if indexPath.section < self.frozenRows || indexPath.item < self.frozenColumns{
            tableCell.backgroundColor = self.frozenColor
        }else{
            if let selectedIndexPath = self.selectedIndexPath,
               selectedIndexPath.section == indexPath.section {
                tableCell.backgroundColor = self.selectedColor
            }else if indexPath.section % 2 == 0{
                tableCell.backgroundColor = UIColor.systemBackground
            }else{
                tableCell.backgroundColor = UIColor.systemGroupedBackground
            }
        }
    }

    func prepare() {
        self.cellHolders  = []
        self.geometries = []
    }

    //MARK: - common logic
    private func cellHolder(at indexPath : IndexPath) -> CellHolder? {
        let index = indexPath.section * self.columnsCount + indexPath.item
        if index < self.cellHolders.count {
            return self.cellHolders[index]
        }else{
            return nil
        }
    }
    
    func size(at indexPath: IndexPath) -> CGSize {
        if let holder = self.cellHolder(at: indexPath) {
            switch holder {
            case .attributedString(let attributedString):
                return attributedString.size()
            case .numberWithUnit,.measurement,.compoundMeasurement:
                return self.geometries[indexPath.item].totalSize
            }
        }else{
            return CGSize.zero
        }
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return self.rowsCount
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.columnsCount
    }
    
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let holder = self.cellHolder(at: indexPath) {
            switch holder {
            case .attributedString(let attributedString):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TableCollectionViewCell", for: indexPath)
                if let tableCell = cell as? TableCollectionViewCell {
                    tableCell.label.attributedText = attributedString
                }
                self.setBackgroundColor(for: cell, itemAt: indexPath)
                
                return cell
            case .numberWithUnit(let nu,let attr):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "NumberWithUnitCollectionViewCell", for: indexPath)
                if let nuCell = cell as? RZNumberWithUnitCollectionViewCell {
                    nuCell.numberWithUnitView.numberWithUnit = nu
                    nuCell.numberWithUnitView.geometry = self.geometries[indexPath.item]
                    nuCell.numberWithUnitView.attributes = attr
                }
                self.setBackgroundColor(for: cell, itemAt: indexPath)
                return cell
            case .measurement(let me, let formatter, let attr):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MeasurementCollectionViewCell", for: indexPath)
                if let nuCell = cell as? MeasurementCollectionViewCell {
                    nuCell.measurementView.measurement = me
                    nuCell.measurementView.formatter = MeasurementView.Formatter.measurement(formatter)
                    nuCell.measurementView.geometry = self.geometries[indexPath.item]
                    nuCell.measurementView.attributes = attr
                }
                self.setBackgroundColor(for: cell, itemAt: indexPath)
                return cell
            case .compoundMeasurement(let me, let comp, let attr):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MeasurementCollectionViewCell", for: indexPath)
                if let nuCell = cell as? MeasurementCollectionViewCell {
                    nuCell.measurementView.measurement = me
                    nuCell.measurementView.formatter = MeasurementView.Formatter.compound(comp)
                    nuCell.measurementView.geometry = self.geometries[indexPath.item]
                    nuCell.measurementView.attributes = attr
                }
                self.setBackgroundColor(for: cell, itemAt: indexPath)
                return cell

            }
        }else{
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TableCollectionViewCell", for: indexPath)
            self.setBackgroundColor(for: cell, itemAt: indexPath)
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        var indexSection : [Int] = []
        if let selectedIndexPath = self.selectedIndexPath {
            indexSection.append(selectedIndexPath.section)
            
            if selectedIndexPath.section == indexPath.section {
                self.selectedIndexPath = nil
            }else{
                self.selectedIndexPath = indexPath
                indexSection.append(indexPath.section)
            }
        }else{
            indexSection.append(indexPath.section)
            self.selectedIndexPath = indexPath
        }
        for i in indexSection {
            collectionView.reloadSections(IndexSet(integer:i))
        }
        if let callback = self.indexPathSelectedCallback {
            callback(self.selectedIndexPath)
        }
    }


}
