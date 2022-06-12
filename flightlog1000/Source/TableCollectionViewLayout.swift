//
//  Table.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 11/05/2022.
//

import UIKit
import RZUtils
import OSLog

protocol TableCollectionDelegate : AnyObject {
    var frozenColumns : Int { get }
    var frozenRows : Int { get }

    func attributedString(at : IndexPath) -> NSAttributedString
    
    func prepare()
}

class TableCollectionViewLayout: UICollectionViewLayout {

    weak var tableCollectionDelegate : TableCollectionDelegate? = nil {
        didSet { self.itemAttributes.removeAll() }
    }
    
    var itemAttributes = [[UICollectionViewLayoutAttributes]]()
    
    private var cellSizes : [CGSize] = []
    private(set) var columnsWidth : [CGFloat] = []
    private(set) var rowsHeight : [CGFloat] = []
    
    private(set) var contentSize : CGSize = CGSize.zero

    override func prepare() {
        guard let collectionView = collectionView,
              let tableCollectionDelegate = self.tableCollectionDelegate,
              collectionView.numberOfSections > 0
        else {
            return
        }
        
        if itemAttributes.count != collectionView.numberOfSections {
            tableCollectionDelegate.prepare()
            self.computeGeometry()
            self.buildCellsAttributes()
        }
        self.updateFrozenCellsAttributes()
    }
    
    override var collectionViewContentSize: CGSize {
        return self.contentSize
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return itemAttributes[indexPath.section][indexPath.item]
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributes : [UICollectionViewLayoutAttributes] = []
        for section in itemAttributes {
            let filteredArray = section.filter { obj in return rect.intersects(obj.frame) }
            attributes.append(contentsOf: filteredArray)
        }
        return attributes
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
    
    //MARK: - utils
    func buildCellsAttributes() {
        guard let collectionView = collectionView,
              let sizeDelegate = self.tableCollectionDelegate
        else{
            return
        }
        sizeDelegate.prepare()
        

        let frozenColumns = sizeDelegate.frozenColumns
        let frozenRows = sizeDelegate.frozenRows

        self.itemAttributes = []
        var y : CGFloat = 0

        for section in 0..<collectionView.numberOfSections {
            var x : CGFloat = 0
            var sectionAttributes : [UICollectionViewLayoutAttributes] = []
            for item in 0..<collectionView.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: item, section: section)
                let size = self.size(at: indexPath)
                let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                attributes.frame = frame
                
                // top rows always on top
                if section < frozenRows && item < frozenColumns {
                    attributes.zIndex = 1024
                }
                else if section < frozenRows || item < frozenColumns{
                    attributes.zIndex = 1023
                }
                
                sectionAttributes.append(attributes)
                x += size.width
            }
            self.itemAttributes.append(sectionAttributes)
            let size = self.size(at: IndexPath(item: 0, section: section))
            y += size.height
        }        
    }
    
    func updateFrozenCellsAttributes() {
        guard let collectionView = collectionView,
              let sizeDelegate = self.tableCollectionDelegate
        else{
            return
        }
        
        
        // Now position the frozen cell at the top and left
        let frozenColumns = sizeDelegate.frozenColumns
        let frozenRows = sizeDelegate.frozenRows
        
        // var because should update when more than 1 row
        var y = collectionView.contentOffset.y
        for section in 0..<collectionView.numberOfSections {
            var x = collectionView.contentOffset.x
            var maxHeight : CGFloat = 0.0
            for item in 0..<collectionView.numberOfItems(inSection: section) {
                if section >= frozenRows && item >= frozenColumns {
                    continue
                }
                if let attributes = layoutAttributesForItem(at: IndexPath(item: item, section: section)) {
                    if section < frozenRows {
                        // update y for previous frozen rows
                        var frame = attributes.frame
                        frame.origin.y = y
                        attributes.frame = frame
                        maxHeight = max(maxHeight, frame.size.height)
                        
                    }
                    if item < frozenColumns {
                        // update x for previous frozen cols
                        x += 0
                        var frame = attributes.frame
                        frame.origin.x = x
                        attributes.frame = frame
                        x += frame.size.width
                    }
                }
            }
            y += maxHeight
        }
    }
    
    
    func size(at: IndexPath) -> CGSize {
        guard self.columnsWidth.count > 0 else { return CGSize.zero }
        return CGSize(width: self.columnsWidth[at.item], height: self.rowsHeight[at.section])
    }

    private func computeGeometry() {
        
        self.contentSize = CGSize.zero
        self.cellSizes  = []
        self.columnsWidth  = []
        self.rowsHeight = []
        let marginMultiplier = CGSize(width: 1.2, height: 1.2)
        
        guard let collectionView = collectionView,
              let tableCollectionDelegate = self.tableCollectionDelegate
        else{
            return
        }

        if collectionView.numberOfSections > 0 {
            for section in 0..<collectionView.numberOfSections {
                var rowHeight : CGFloat = 0.0
                for item in 00..<collectionView.numberOfItems(inSection: section) {
                    let indexPath = IndexPath(item: item, section: section)
                    let textAttributed = tableCollectionDelegate.attributedString(at: indexPath)
                    let textSize = textAttributed.size()
                    self.cellSizes.append(textSize)
                    if item < self.columnsWidth.count {
                        self.columnsWidth[item] = max(self.columnsWidth[item], textSize.width*marginMultiplier.width)
                    }else{
                        self.columnsWidth.append(textSize.width * marginMultiplier.width)
                    }
                    rowHeight  = max(rowHeight, textSize.height * marginMultiplier.height)
                }
                self.rowsHeight.append(rowHeight)
                self.contentSize.height += rowHeight
            }
            
            self.contentSize.width = self.columnsWidth.reduce(0.0, +)
        }
    }

}
