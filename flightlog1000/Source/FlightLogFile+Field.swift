//
//  FlightData+Constants.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import Foundation

extension FlightLogFile {
    static func fields(_ fs : [Field]) -> [String] {
        return fs.map { $0.rawValue }
    }
    
    static func field(_ f : Field) -> String {
        return f.rawValue
    }
    
    enum Field : String {
        case AtvWpt = "AtvWpt"
        case Latitude = "Latitude"
        case Longitude = "Longitude"
        case AltInd = "AltInd"
        case BaroA = "BaroA"
        case AltMSL = "AltMSL"
        case OAT = "OAT"
        case IAS = "IAS"
        case GndSpd = "GndSpd"
        case VSpd = "VSpd"
        case Pitch = "Pitch"
        case Roll = "Roll"
        case LatAc = "LatAc"
        case NormAc = "NormAc"
        case HDG = "HDG"
        case TRK = "TRK"
        case volt1 = "volt1"
        case volt2 = "volt2"
        case amp1 = "amp1"
        case FQtyL = "FQtyL"
        case FQtyR = "FQtyR"
        case E1_FFlow = "E1 FFlow"
        case E1_OilT = "E1 OilT"
        case E1_OilP = "E1 OilP"
        case E1_MAP = "E1 MAP"
        case E1_RPM = "E1 RPM"
        case E1_PctPwr = "E1 %Pwr"
        case E1_CHT1 = "E1 CHT1"
        case E1_CHT2 = "E1 CHT2"
        case E1_CHT3 = "E1 CHT3"
        case E1_CHT4 = "E1 CHT4"
        case E1_CHT5 = "E1 CHT5"
        case E1_CHT6 = "E1 CHT6"
        case E1_EGT1 = "E1 EGT1"
        case E1_EGT2 = "E1 EGT2"
        case E1_EGT3 = "E1 EGT3"
        case E1_EGT4 = "E1 EGT4"
        case E1_EGT5 = "E1 EGT5"
        case E1_EGT6 = "E1 EGT6"
        case E1_TIT1 = "E1 TIT1"
        case E1_TIT2 = "E1 TIT2"
        case E1_Torq = "E1 Torq"
        case E1_NG = "E1 NG"
        case E1_ITT = "E1 ITT"
        case E2_FFlow = "E2 FFlow"
        case E2_MAP = "E2 MAP"
        case E2_RPM = "E2 RPM"
        case E2_Torq = "E2 Torq"
        case E2_NG = "E2 NG"
        case E2_ITT = "E2 ITT"
        case AltGPS = "AltGPS"
        case TAS = "TAS"
        case HSIS = "HSIS"
        case CRS = "CRS"
        case NAV1 = "NAV1"
        case NAV2 = "NAV2"
        case COM1 = "COM1"
        case COM2 = "COM2"
        case HCDI = "HCDI"
        case VCDI = "VCDI"
        case WndSpd = "WndSpd"
        case WndDr = "WndDr"
        case WptDst = "WptDst"
        case WptBrg = "WptBrg"
        case MagVar = "MagVar"
        case AfcsOn = "AfcsOn"
        case RollM = "RollM"
        case PitchM = "PitchM"
        case RollC = "RollC"
        case PichC = "PichC"
        case VSpdG = "VSpdG"
        case GPSfix = "GPSfix"
        case HAL = "HAL"
        case VAL = "VAL"
        case HPLwas = "HPLwas"
        case HPLfd = "HPLfd"
        case VPLwas = "VPLwas"
    }
}
