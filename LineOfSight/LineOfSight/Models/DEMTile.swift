//
//  DEMTile.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/21/25.
//

import Foundation
import CoreLocation

/// Represents a USGS 3DEP DEM tile with elevation data
struct DEMTile {
    /// Width of the tile in pixels (typically 3601 for 1 arc-second or 10812 for 1/3 arc-second)
    let width: Int
    
    /// Height of the tile in pixels
    let height: Int
    
    /// Longitudinal cell size in degrees (delta lon per pixel)
    let cellSizeLon: Double
    /// Latitudinal cell size in degrees (delta lat per pixel)
    let cellSizeLat: Double
    
    /// Northwest corner latitude (top edge)
    let originLatitude: Double
    
    /// Northwest corner longitude (left edge)
    let originLongitude: Double
    
    /// Flat array of elevation values in meters (row-major order, starting from NW corner)
    /// Index calculation: row * width + col
    let elevations: [Float]
    
    /// The tile coordinate this data represents
    let tileCoordinate: TileCoordinate
    
    /// Initialize a DEM tile
    init(
        width: Int,
        height: Int,
        cellSizeLon: Double,
        cellSizeLat: Double,
        originLatitude: Double,
        originLongitude: Double,
        elevations: [Float],
        tileCoordinate: TileCoordinate
    ) {
        self.width = width
        self.height = height
        self.cellSizeLon = cellSizeLon
        self.cellSizeLat = cellSizeLat
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.elevations = elevations
        self.tileCoordinate = tileCoordinate
    }
    
    /// Get elevation at a specific coordinate using bilinear interpolation
    /// - Parameter coordinate: The geographic coordinate
    /// - Returns: Interpolated elevation in meters, or nil if coordinate is outside tile bounds
    func elevation(at coordinate: CLLocationCoordinate2D) -> Double? {
        // Convert coordinate to pixel space
        // Note: Row increases from north to south (lat decreases)
        // Column increases from west to east (lon increases)
        let x = (coordinate.longitude - originLongitude) / cellSizeLon
        let y = (originLatitude - coordinate.latitude) / cellSizeLat
        
        // Check bounds
        guard x >= 0, x < Double(width - 1),
              y >= 0, y < Double(height - 1) else {
            return nil
        }
        
        // Get the four surrounding pixels
        let x0 = Int(floor(x))
        let x1 = x0 + 1
        let y0 = Int(floor(y))
        let y1 = y0 + 1
        
        // Get fractional parts for interpolation
        let fx = x - Double(x0)
        let fy = y - Double(y0)
        
        // Get elevation values at the four corners
        let z00 = Double(elevations[y0 * width + x0])
        let z10 = Double(elevations[y0 * width + x1])
        let z01 = Double(elevations[y1 * width + x0])
        let z11 = Double(elevations[y1 * width + x1])
        
        // DEBUG: Log tile query details
        // print("📍 Tile Query: coord=(\(String(format: "%.6f", coordinate.latitude)),\(String(format: "%.6f", coordinate.longitude)))")
        // print("   Origin: (\(String(format: "%.6f", originLatitude)),\(String(format: "%.6f", originLongitude)))")
        // print("   Pixel: x=\(String(format: "%.2f", x)), y=\(String(format: "%.2f", y))")
        // print("   Corners: z00=\(String(format: "%.1f", z00)), z10=\(String(format: "%.1f", z10)), z01=\(String(format: "%.1f", z01)), z11=\(String(format: "%.1f", z11))")
        // print("   Size: \(width)x\(height), cellSizeLon=\(cellSizeLon), cellSizeLat=\(cellSizeLat)")
        
        // Bilinear interpolation
        let z0 = z00 * (1 - fx) + z10 * fx
        let z1 = z01 * (1 - fx) + z11 * fx
        let z = z0 * (1 - fy) + z1 * fy
        
        // print("   Result: \(String(format: "%.1f", z))m")
        
        return z
    }
    
    /// Check if a coordinate is within this tile's bounds
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let minLat = originLatitude - Double(height - 1) * cellSizeLat
        let maxLat = originLatitude
        let minLon = originLongitude
        let maxLon = originLongitude + Double(width - 1) * cellSizeLon
        
        return coordinate.latitude >= minLat &&
               coordinate.latitude <= maxLat &&
               coordinate.longitude >= minLon &&
               coordinate.longitude <= maxLon
    }
}

/// Represents the coordinate of a DEM tile in the Web Mercator tile grid
struct TileCoordinate: Hashable, Codable {
    /// Tile X coordinate
    let x: Int
    
    /// Tile Y coordinate
    let y: Int
    
    /// Zoom level (using z=14 for fine-grained detail)
    let z: Int
    
    /// Initialize from a geographic coordinate
    /// - Parameter coordinate: Any coordinate within the desired tile
    /// - Parameter zoom: Zoom level (default 14)
    init(from coordinate: CLLocationCoordinate2D, zoom: Int = 14) {
        self.z = zoom
        
        // Calculate Web Mercator tile coordinates
        // n = 2^z
        let n = Double(1 << zoom)
        
        // x = floor( (lon + 180) / 360 * n )
        self.x = Int(floor((coordinate.longitude + 180.0) / 360.0 * n))
        
        // y = floor( (1 - ln(tan(lat*pi/180) + sec(lat*pi/180)) / pi) / 2 * n )
        let latRad = coordinate.latitude * Double.pi / 180.0
        let y_calc = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / Double.pi) / 2.0 * n
        self.y = Int(floor(y_calc))
    }
    
    /// Initialize with explicit tile coordinates
    init(x: Int, y: Int, z: Int = 14) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    /// Generate the tile filename for caching
    var filename: String {
        return "\(z)_\(x)_\(y).tif"
    }
    
    /// Generate the tile URL using Mapzen/Tilezen elevation tiles
    /// Format: https://s3.amazonaws.com/elevation-tiles-prod/geotiff/{z}/{x}/{y}.tif
    var url: URL {
        let urlString = "https://s3.amazonaws.com/elevation-tiles-prod/geotiff/\(z)/\(x)/\(y).tif"
        return URL(string: urlString)!
    }
    
    /// Get the northwest corner coordinate of this tile in Web Mercator
    var northwestCorner: CLLocationCoordinate2D {
        let n = Double(1 << z)
        
        // Calculate longitude from x
        let lon = Double(x) / n * 360.0 - 180.0
        
        // Calculate latitude from y
        // Inverse of: y = (1 - ln(tan(lat) + sec(lat)) / pi) / 2 * n
        let y_norm = Double(y) / n
        let lat_rad = atan(sinh(Double.pi * (1.0 - 2.0 * y_norm)))
        let lat = lat_rad * 180.0 / Double.pi
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
