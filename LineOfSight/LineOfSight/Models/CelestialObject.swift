//
//  CelestialObject.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import Foundation

/// Represents a celestial object for alignment calculations
struct CelestialObject: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let type: CelestialType
    let magnitude: Double?
    
    init(id: String, name: String, type: CelestialType, magnitude: Double? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.magnitude = magnitude
    }
}

/// Types of celestial objects
enum CelestialType: String, Codable, CaseIterable {
    case sun = "sun"
    case moon = "moon"
    case planet = "planet"
    case star = "star"
    
    var displayName: String {
        switch self {
        case .sun:
            return "Sun"
        case .moon:
            return "Moon"
        case .planet:
            return "Planet"
        case .star:
            return "Star"
        }
    }
    
    var icon: String {
        switch self {
        case .sun:
            return "sun.max.fill"
        case .moon:
            return "moon.fill"
        case .planet:
            return "globe"
        case .star:
            return "star.fill"
        }
    }
    
    var color: String {
        switch self {
        case .sun:
            return "yellow"
        case .moon:
            return "gray"
        case .planet:
            return "blue"
        case .star:
            return "white"
        }
    }
}

/// Predefined celestial objects commonly used for photography
extension CelestialObject {
    static let sun = CelestialObject(
        id: "sun",
        name: "Sun",
        type: .sun,
        magnitude: -26.7
    )
    
    static let moon = CelestialObject(
        id: "moon",
        name: "Moon",
        type: .moon,
        magnitude: -12.6
    )
    
    static let venus = CelestialObject(
        id: "venus",
        name: "Venus",
        type: .planet,
        magnitude: -4.6
    )
    
    static let jupiter = CelestialObject(
        id: "jupiter",
        name: "Jupiter",
        type: .planet,
        magnitude: -2.9
    )
    
    static let mars = CelestialObject(
        id: "mars",
        name: "Mars",
        type: .planet,
        magnitude: -2.9
    )
    
    static let saturn = CelestialObject(
        id: "saturn",
        name: "Saturn",
        type: .planet,
        magnitude: -0.5
    )
    
    static let sirius = CelestialObject(
        id: "sirius",
        name: "Sirius",
        type: .star,
        magnitude: -1.46
    )
    
    static let vega = CelestialObject(
        id: "vega",
        name: "Vega",
        type: .star,
        magnitude: 0.03
    )
    
    static let polaris = CelestialObject(
        id: "polaris",
        name: "Polaris",
        type: .star,
        magnitude: 1.98
    )
    
    /// Default celestial objects for the app
    static let defaultObjects: [CelestialObject] = [
        .sun, .moon, .venus, .jupiter, .mars, .saturn, .sirius, .vega, .polaris
    ]
    
    /// Most commonly photographed objects
    static let popularObjects: [CelestialObject] = [
        .sun, .moon, .venus, .jupiter
    ]
}

/// Celestial coordinate information
struct CelestialCoordinate {
    let rightAscension: Double // in hours
    let declination: Double    // in degrees
    let azimuth: Double       // in degrees
    let elevation: Double     // in degrees (altitude)
    let timestamp: Date
    
    /// Whether the object is above the horizon
    var isVisible: Bool {
        return elevation > 0
    }
    
    /// Whether the object is in twilight conditions (suitable for photography)
    var isTwilightVisible: Bool {
        return elevation > -6 // Civil twilight
    }
}