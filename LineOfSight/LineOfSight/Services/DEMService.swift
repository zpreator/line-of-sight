//
//  DEMService.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/21/25.
//

import Foundation
import CoreLocation

/// High-level service for querying terrain elevation from DEM tiles
actor DEMService {
    
    // MARK: - Properties
    
    private let tileManager: TileManager
    
    // MARK: - Initialization
    
    init(tileManager: TileManager = TileManager()) {
        self.tileManager = tileManager
    }
    
    // MARK: - Public Methods
    
    /// Get elevation at a specific coordinate
    /// - Parameter coordinate: The geographic coordinate
    /// - Returns: Elevation in meters, or nil if data is unavailable
    func elevation(at coordinate: CLLocationCoordinate2D) async -> Double? {
        do {
            let tile = try await tileManager.loadTile(for: coordinate)
            let elevation = tile.elevation(at: coordinate)
            return elevation
        } catch {
            // Fallback to Open-Elevation API for now
            return await getElevationFromAPI(coordinate: coordinate)
        }
    }
    
    /// Fallback: Get elevation from Open-Elevation API
    private func getElevationFromAPI(coordinate: CLLocationCoordinate2D) async -> Double? {
        let urlString = "https://api.open-elevation.com/api/v1/lookup?locations=\(coordinate.latitude),\(coordinate.longitude)"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let firstResult = results.first,
               let elevation = firstResult["elevation"] as? Double {
                return elevation
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    /// Get elevations for multiple coordinates efficiently
    /// - Parameter coordinates: Array of coordinates
    /// - Returns: Array of optional elevations (nil if unavailable)
    func elevations(at coordinates: [CLLocationCoordinate2D]) async -> [Double?] {
        // Group coordinates by tile to minimize tile loads
        var tileGroups: [TileCoordinate: [Int]] = [:]
        
        for (index, coordinate) in coordinates.enumerated() {
            let tileCoord = TileCoordinate(from: coordinate)
            tileGroups[tileCoord, default: []].append(index)
        }
        
        // Initialize results array
        var results: [Double?] = Array(repeating: nil, count: coordinates.count)
        
        // Load each tile and query elevations
        for (tileCoord, indices) in tileGroups {
            do {
                let tile = try await tileManager.loadTile(tileCoordinate: tileCoord)
                
                for index in indices {
                    let coordinate = coordinates[index]
                    results[index] = tile.elevation(at: coordinate)
                }
            } catch {
                print("Failed to load tile \(tileCoord.filename): \(error)")
                // Indices for this tile will remain nil
            }
        }
        
        return results
    }
    
    /// Preload tiles for a specific area to enable fast lookups
    /// - Parameters:
    ///   - center: Center coordinate
    ///   - radiusKm: Radius in kilometers
    func preloadArea(around center: CLLocationCoordinate2D, radiusKm: Double) async {
        await tileManager.preloadTiles(around: center, radiusKm: radiusKm)
    }
    
    /// Clear all cached tiles from memory
    func clearMemoryCache() async {
        await tileManager.clearMemoryCache()
    }
    
    /// Clear all cached tiles from disk
    func clearDiskCache() async throws {
        try await tileManager.clearDiskCache()
    }
    
    /// Get the size of the disk cache
    func cacheSize() async throws -> Int64 {
        return try await tileManager.cacheSize()
    }
    
    /// Sample elevation along a path
    /// - Parameters:
    ///   - start: Starting coordinate
    ///   - end: Ending coordinate
    ///   - samples: Number of samples along the path
    /// - Returns: Array of elevations (nil for unavailable points)
    func elevationProfile(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, samples: Int) async -> [Double?] {
        var coordinates: [CLLocationCoordinate2D] = []
        
        for i in 0..<samples {
            let fraction = Double(i) / Double(samples - 1)
            let lat = start.latitude + (end.latitude - start.latitude) * fraction
            let lon = start.longitude + (end.longitude - start.longitude) * fraction
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        
        return await elevations(at: coordinates)
    }
}
