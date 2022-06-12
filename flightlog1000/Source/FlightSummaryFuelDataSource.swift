//
//  FlightSummaryFuelDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 12/06/2022.
//

import UIKit
import OSLog

class FlightSummaryFuelDataSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, TableCollectionDelegate  {
    
    let flightSummary : FlightSummary
    let displayContext : DisplayContext
    
    private var attributedCells : [NSAttributedString] = []

    var frozenColumns : Int = 1
    var frozenRows : Int = 1
    
    //               Total    Left   Right
    //    Start
    //    End
    //    Remaining
    
    init(flightSummary : FlightSummary, displayContext : DisplayContext = DisplayContext()){
        self.flightSummary = flightSummary
        self.displayContext = displayContext
        
    }
    
    //MARK: - delegate
        
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func prepare() {
        
        self.attributedCells  = []
        
        for title in [ "Fuel", "Total", "Left", "Right" ] {
            self.attributedCells.append(NSAttributedString(string: title, attributes: self.titleAttributes))
        }
        for (name,fuel) in [("Start", self.flightSummary.fuelStart),
                          ("End", self.flightSummary.fuelEnd),
                          ("Used", self.flightSummary.fuelUsed)
        ] {
            self.attributedCells.append(NSAttributedString(string: name, attributes: self.titleAttributes))
            self.attributedCells.append(NSAttributedString(string: self.displayContext.formatValue(gallon: fuel.total)))
            self.attributedCells.append(NSAttributedString(string: self.displayContext.formatValue(gallon: fuel.left)))
            self.attributedCells.append(NSAttributedString(string: self.displayContext.formatValue(gallon: fuel.right)))
        }
    }
    
    func attributedString(at indexPath : IndexPath) -> NSAttributedString {
        let index = indexPath.section * 4 + indexPath.item
        return self.attributedCells[index]
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 4
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 4
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TableCollectionViewCell", for: indexPath)
        if let tableCell = cell as? TableCollectionViewCell {
            tableCell.label.attributedText = self.attributedString(at: indexPath)
            
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
