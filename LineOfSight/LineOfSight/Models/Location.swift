//
//  Location.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import Foundation
import CoreLocation

/// Represents a specific location with coordinate and elevation data
struct Location: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String?
    let coordinate: CLLocationCoordinate2D
    let elevation: Double // in meters
    let timestamp: Date
    let source: LocationSource
    let precision: LocationPrecision
    
    init(name: String? = nil, 
         coordinate: CLLocationCoordinate2D, 
         elevation: Double, 
         source: LocationSource = .map, 
         precision: LocationPrecision = .approximate) {
        self.id = UUID()
        self.name = name
        self.coordinate = coordinate
        self.elevation = elevation
        self.timestamp = Date()
        self.source = source
        self.precision = precision
    }
}

/// Source of the location data
enum LocationSource: String, Codable, CaseIterable {
    case map = "map"
    case camera = "camera"
    
    var displayName: String {
        switch self {
        case .map:
            return "Map Selection"
        case .camera:
            return "Camera Triangulation"
        }
    }
    
    var icon: String {
        switch self {
        case .map:
            return "map"
        case .camera:
            return "camera"
        }
    }
}

/// Precision level of the location data
enum LocationPrecision: String, Codable, CaseIterable {
    case approximate = "approximate"
    case precise = "precise"
    
    var displayName: String {
        switch self {
        case .approximate:
            return "Approximate"
        case .precise:
            return "Precise"
        }
    }
    
    var description: String {
        switch self {
        case .approximate:
            return "±10-50m accuracy"
        case .precise:
            return "±1-5m accuracy"
        }
    }
}

// MARK: - CLLocationCoordinate2D Codable Extension
extension CLLocationCoordinate2D: @retroactive Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}

// MARK: - CLLocationCoordinate2D Equatable Extension
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return abs(lhs.latitude - rhs.latitude) < 0.000001 && 
               abs(lhs.longitude - rhs.longitude) < 0.000001
    }
}