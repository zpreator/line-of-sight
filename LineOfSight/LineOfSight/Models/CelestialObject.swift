//
//  CelestialObject.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import Foundation

// MARK: - Supporting Types

// MARK: - Celestial Object Model

/// Represents a celestial object (currently only Sun, but extensible)
struct CelestialObject: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let type: CelestialType
    // Add more properties for future expansion if needed
    
    init(id: String, name: String, type: CelestialType) {
        self.id = id
        self.name = name
        self.type = type
    }
}

/// Types of celestial objects
enum CelestialType: String, Codable, Equatable, Hashable {
    case sun
    // Add more cases for future expansion
    
    var displayName: String {
        switch self {
        case .sun:
            return "Sun"
        }
    }
    
    var icon: String {
        switch self {
        case .sun:
            return "sun.max.fill"
        }
    }
    
    var color: String {
        switch self {
        case .sun:
            return "yellow"
        }
    }
}

extension CelestialObject {
    static let sun = CelestialObject(
        id: "sun",
        name: "Sun",
        type: .sun
    )
    
    static let defaultObjects: [CelestialObject] = [
        .sun
    ]
}

// Remove CelestialCoordinate, not needed for current scope