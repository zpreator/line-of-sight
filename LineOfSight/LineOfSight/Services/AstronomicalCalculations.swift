//
//  AstronomicalCalculations.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import Foundation
import CoreLocation
import SwiftAA
/// Service for astronomical calculations (Sun and POI only)
class AstronomicalCalculations {
    /// Generic position calculation for any celestial object
    static func position(for object: CelestialObject, at date: Date, coordinate: CLLocationCoordinate2D) -> (azimuth: Double, elevation: Double) {
        let julianDay = JulianDay(date)
        let geographicCoordinates = GeographicCoordinates(
            positivelyWestwardLongitude: Degree(-coordinate.longitude),
            latitude: Degree(coordinate.latitude),
            altitude: Meter(0)
        )
        switch object.type {
        case .sun:
            let sun = Sun(julianDay: julianDay)
            let sunCoordinates = sun.equatorialCoordinates
            let horizontalCoordinates = sunCoordinates.makeHorizontalCoordinates(
                for: geographicCoordinates,
                at: julianDay
            )
            // Normalize azimuth to be measured clockwise from North
            // SwiftAA azimuth is clockwise from South; convert by +180° modulo 360
            let azFromSouth = horizontalCoordinates.azimuth.value
            let azFromNorth = fmod(azFromSouth + 180.0, 360.0)
            return (azimuth: azFromNorth, elevation: horizontalCoordinates.altitude.value)
        // Future celestial types can be added here
        }
    }

    /// Calculate the sun's position for a given date and location (legacy, uses generic method)
    static func sunPosition(for date: Date, at location: CLLocationCoordinate2D) -> (azimuth: Double, elevation: Double) {
        return position(for: .sun, at: date, coordinate: location)
    }

    /// Calculate the ground-projected line between POI and any celestial object
    static func projectedLineToCelestialObject(
        poi: CLLocationCoordinate2D,
        object: CelestialObject,
        date: Date,
        distanceKm: Double = 10.0
    ) -> (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) {
        // Get object's azimuth at POI
        let pos = position(for: object, at: date, coordinate: poi)
        // Project a line from POI in the direction of the object's azimuth
        let azimuthRad = pos.azimuth * Double.pi / 180.0
        let earthRadiusKm = 6371.0
        let lat1 = poi.latitude * Double.pi / 180.0
        let lon1 = poi.longitude * Double.pi / 180.0
        let lat2 = asin(sin(lat1) * cos(distanceKm / earthRadiusKm) + cos(lat1) * sin(distanceKm / earthRadiusKm) * cos(azimuthRad))
        let lon2 = lon1 + atan2(
            sin(azimuthRad) * sin(distanceKm / earthRadiusKm) * cos(lat1),
            cos(distanceKm / earthRadiusKm) - sin(lat1) * sin(lat2)
        )
        let endLat = lat2 * 180.0 / Double.pi
        let endLon = lon2 * 180.0 / Double.pi
        return (start: poi, end: CLLocationCoordinate2D(latitude: endLat, longitude: endLon))
    }
}
