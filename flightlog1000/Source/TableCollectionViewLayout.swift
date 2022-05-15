//
//  Table.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 11/05/2022.
//

import UIKit

protocol TableCollectionSizeDelegate : AnyObject {
    var frozenColumns : Int { get }
    var frozenRows : Int { get }
    
    var contentSize : CGSize { get }
    
    func size(at : IndexPath) -> CGSize
    
    func prepare()
}

class TableCollectionViewLayout: UICollectionViewLayout {

    weak var sizeDelegate : TableCollectionSizeDelegate? = nil
    
    var itemAttributes = [[UICollectionViewLayoutAttributes]]()
    
    override func prepare() {
        guard let collectionView = collectionView,
              collectionView.numberOfSections > 0
        else {
            return
        }
        
        if itemAttributes.count != collectionView.numberOfSections {
            self.buildCellsAttributes()
        }
        self.updateFrozenCellsAttributes()
    }
    
    override var collectionViewContentSize: CGSize {
        return self.sizeDelegate?.contentSize ?? CGSize.zero
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
              let sizeDelegate = self.sizeDelegate
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
                let size = sizeDelegate.size(at: indexPath)
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
            let size = sizeDelegate.size(at: IndexPath(item: 0, section: section))
            y += size.height
        }        
    }
    
    func updateFrozenCellsAttributes() {
        guard let collectionView = collectionView,
              let sizeDelegate = self.sizeDelegate
        else{
            return
        }
        
        // Now position the frozen cell at the top and left
        let frozenColumns = sizeDelegate.frozenColumns
        let frozenRows = sizeDelegate.frozenRows
        
        var y = collectionView.contentOffset.y
        for section in 0..<collectionView.numberOfSections {
            var x = collectionView.contentOffset.x
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
        }
    }
}
