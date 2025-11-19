//
//  AstronomicalCalculations.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import Foundation
import CoreLocation

/// Service for astronomical calculations and celestial object positioning
class AstronomicalCalculations {
    
    // MARK: - Constants
    private static let degreesToRadians = Double.pi / 180.0
    private static let radiansToDegrees = 180.0 / Double.pi
    
    // MARK: - Sun Calculations
    
    /// Calculate the sun's position for a given date and location
    static func sunPosition(for date: Date, at location: CLLocationCoordinate2D) -> CelestialCoordinate {
        let julianDay = julianDay(for: date)
        let (ra, dec) = sunRightAscensionDeclination(julianDay: julianDay)
        let (azimuth, elevation) = horizontalCoordinates(
            rightAscension: ra,
            declination: dec,
            latitude: location.latitude,
            longitude: location.longitude,
            julianDay: julianDay
        )
        
        return CelestialCoordinate(
            rightAscension: ra,
            declination: dec,
            azimuth: azimuth,
            elevation: elevation,
            timestamp: date
        )
    }
    
    /// Calculate sunrise time for a given date and location
    static func sunrise(for date: Date, at location: CLLocationCoordinate2D) -> Date? {
        return sunEvent(for: date, at: location, isRise: true)
    }
    
    /// Calculate sunset time for a given date and location
    static func sunset(for date: Date, at location: CLLocationCoordinate2D) -> Date? {
        return sunEvent(for: date, at: location, isRise: false)
    }
    
    // MARK: - Moon Calculations
    
    /// Calculate the moon's position for a given date and location
    static func moonPosition(for date: Date, at location: CLLocationCoordinate2D) -> CelestialCoordinate {
        let julianDay = julianDay(for: date)
        let (ra, dec) = moonRightAscensionDeclination(julianDay: julianDay)
        let (azimuth, elevation) = horizontalCoordinates(
            rightAscension: ra,
            declination: dec,
            latitude: location.latitude,
            longitude: location.longitude,
            julianDay: julianDay
        )
        
        return CelestialCoordinate(
            rightAscension: ra,
            declination: dec,
            azimuth: azimuth,
            elevation: elevation,
            timestamp: date
        )
    }
    
    /// Calculate moon phase for a given date
    static func moonPhase(for date: Date) -> Double {
        let julianDay = julianDay(for: date)
        let newMoonJD = 2451549.5 // New moon on Jan 6, 2000
        let lunarCycle = 29.53058867 // days
        
        let daysSinceNewMoon = (julianDay - newMoonJD).truncatingRemainder(dividingBy: lunarCycle)
        return daysSinceNewMoon / lunarCycle
    }
    
    // MARK: - General Celestial Calculations
    
    /// Calculate position for any celestial object given its RA/Dec
    static func celestialObjectPosition(
        rightAscension: Double,
        declination: Double,
        for date: Date,
        at location: CLLocationCoordinate2D
    ) -> CelestialCoordinate {
        let julianDay = julianDay(for: date)
        let (azimuth, elevation) = horizontalCoordinates(
            rightAscension: rightAscension,
            declination: declination,
            latitude: location.latitude,
            longitude: location.longitude,
            julianDay: julianDay
        )
        
        return CelestialCoordinate(
            rightAscension: rightAscension,
            declination: declination,
            azimuth: azimuth,
            elevation: elevation,
            timestamp: date
        )
    }
    
    /// Calculate when a celestial object will be at a specific azimuth/elevation
    static func transitTime(
        for celestialObject: CelestialObject,
        targetAzimuth: Double,
        targetElevation: Double,
        date: Date,
        location: CLLocationCoordinate2D
    ) -> Date? {
        // Simplified implementation - would need more sophisticated calculation in production
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        // Check every 15 minutes throughout the day
        for minutes in stride(from: 0, to: 1440, by: 15) {
            let testDate = startOfDay.addingTimeInterval(TimeInterval(minutes * 60))
            let position: CelestialCoordinate
            
            switch celestialObject.type {
            case .sun:
                position = sunPosition(for: testDate, at: location)
            case .moon:
                position = moonPosition(for: testDate, at: location)
            default:
                // For stars and planets, would need proper ephemeris data
                continue
            }
            
            // Check if within tolerance (±2 degrees)
            if abs(position.azimuth - targetAzimuth) < 2.0 &&
               abs(position.elevation - targetElevation) < 2.0 {
                return testDate
            }
        }
        
        return nil
    }
    
    // MARK: - Utility Functions
    
    /// Convert date to Julian Day
    private static func julianDay(for date: Date) -> Double {
        let timeInterval = date.timeIntervalSince1970
        return (timeInterval / 86400.0) + 2440587.5
    }
    
    /// Calculate Greenwich Mean Sidereal Time
    private static func greenwichMeanSiderealTime(julianDay: Double) -> Double {
        let t = (julianDay - 2451545.0) / 36525.0
        var gmst = 280.46061837 + 360.98564736629 * (julianDay - 2451545.0) + 0.000387933 * t * t - (t * t * t) / 38710000.0
        
        gmst = gmst.truncatingRemainder(dividingBy: 360.0)
        if gmst < 0 { gmst += 360.0 }
        
        return gmst
    }
    
    /// Convert equatorial coordinates to horizontal coordinates
    private static func horizontalCoordinates(
        rightAscension: Double,
        declination: Double,
        latitude: Double,
        longitude: Double,
        julianDay: Double
    ) -> (azimuth: Double, elevation: Double) {
        let gmst = greenwichMeanSiderealTime(julianDay: julianDay)
        let localSiderealTime = gmst + longitude
        let hourAngle = localSiderealTime - rightAscension * 15.0 // Convert RA from hours to degrees
        
        let lat = latitude * degreesToRadians
        let dec = declination * degreesToRadians
        let ha = hourAngle * degreesToRadians
        
        let sinElevation = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)
        let elevation = asin(sinElevation) * radiansToDegrees
        
        let cosAzimuth = (sin(dec) - sin(lat) * sinElevation) / (cos(lat) * cos(asin(sinElevation)))
        let sinAzimuth = -sin(ha) * cos(dec) / cos(asin(sinElevation))
        
        var azimuth = atan2(sinAzimuth, cosAzimuth) * radiansToDegrees
        azimuth = azimuth + 180.0 // Convert to 0-360 range
        if azimuth >= 360.0 { azimuth -= 360.0 }
        
        return (azimuth: azimuth, elevation: elevation)
    }
    
    /// Calculate sun's right ascension and declination (simplified)
    private static func sunRightAscensionDeclination(julianDay: Double) -> (rightAscension: Double, declination: Double) {
        let n = julianDay - 2451545.0
        let l = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360.0)
        let g = (357.528 + 0.9856003 * n) * degreesToRadians
        let lambda = (l + 1.915 * sin(g) + 0.020 * sin(2 * g)) * degreesToRadians
        
        let epsilon = 23.439 * degreesToRadians
        let alpha = atan2(cos(epsilon) * sin(lambda), cos(lambda)) * radiansToDegrees / 15.0
        let delta = asin(sin(epsilon) * sin(lambda)) * radiansToDegrees
        
        return (rightAscension: alpha < 0 ? alpha + 24 : alpha, declination: delta)
    }
    
    /// Calculate moon's right ascension and declination (very simplified)
    private static func moonRightAscensionDeclination(julianDay: Double) -> (rightAscension: Double, declination: Double) {
        let t = (julianDay - 2451545.0) / 36525.0
        
        // Simplified lunar calculations (production would use more precise algorithms)
        let l = 218.316 + 481267.881 * t // Mean longitude
        let m = 134.963 + 477198.868 * t // Mean anomaly
        
        let lambda = (l + 6.289 * sin(m * degreesToRadians)) * degreesToRadians
        let beta = 5.128 * sin((93.272 + 483202.019 * t) * degreesToRadians) * degreesToRadians
        
        let epsilon = 23.439 * degreesToRadians
        let alpha = atan2(cos(epsilon) * sin(lambda) - tan(beta) * sin(epsilon), cos(lambda)) * radiansToDegrees / 15.0
        let delta = asin(sin(epsilon) * sin(lambda) * cos(beta) + cos(epsilon) * sin(beta)) * radiansToDegrees
        
        return (rightAscension: alpha < 0 ? alpha + 24 : alpha, declination: delta)
    }
    
    /// Calculate sun rise/set times
    private static func sunEvent(for date: Date, at location: CLLocationCoordinate2D, isRise: Bool) -> Date? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let startOfDay = calendar.date(from: components) else { return nil }
        
        let lat = location.latitude * degreesToRadians
        let julianDay = julianDay(for: startOfDay)
        let (_, declination) = sunRightAscensionDeclination(julianDay: julianDay)
        let dec = declination * degreesToRadians
        
        // Calculate hour angle for sunrise/sunset (when sun is at -0.833 degrees)
        let zenith = 90.833 * degreesToRadians
        let cosH = (cos(zenith) - sin(lat) * sin(dec)) / (cos(lat) * cos(dec))
        
        // Check if sun never rises or never sets
        if cosH > 1 || cosH < -1 { return nil }
        
        let h = acos(cosH) * radiansToDegrees
        let t = isRise ? (360 - h) / 15.0 : h / 15.0
        
        let timeInterval = TimeInterval(t * 3600)
        return startOfDay.addingTimeInterval(timeInterval)
    }
}