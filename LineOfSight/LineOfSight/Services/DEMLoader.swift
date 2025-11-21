//
//  DEMLoader.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/21/25.
//

import Foundation
import CoreGraphics
import ImageIO
import CoreLocation

/// Loads and parses GeoTIFF DEM files into DEMTile structures
class DEMLoader {
    
    /// Load a DEM tile from a GeoTIFF file
    /// - Parameters:
    ///   - url: URL to the GeoTIFF file
    ///   - tileCoordinate: The tile coordinate this file represents
    /// - Returns: Parsed DEMTile
    func loadDEMTile(from url: URL, tileCoordinate: TileCoordinate) async throws -> DEMTile {
        // Load image source
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw DEMLoaderError.failedToLoadImage
        }
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw DEMLoaderError.failedToLoadImage
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Get the northwest corner from the tile coordinate (current tile)
        let corner = tileCoordinate.northwestCorner
        
        // Determine cell sizes. There are two cases:
        // 1. Degree-based USGS 1-degree tiles (e.g., 10812 or 3601 width) -> uniform 1 degree span
        // 2. Web Mercator tiles (Mapzen) -> derive span from adjacent tile coordinates
        let isDegreeTile = (width == 10812 || width == 3601)
        let cellSizeLon: Double
        let cellSizeLat: Double
        if isDegreeTile {
            let degSpan = 1.0 // tile covers exactly 1 degree in lon and (approximately) lat
            cellSizeLon = degSpan / Double(width - 1)
            cellSizeLat = degSpan / Double(height - 1)
        } else {
            // Adjacent tile northwest corners
            let eastCorner = TileCoordinate(x: tileCoordinate.x + 1, y: tileCoordinate.y, z: tileCoordinate.z).northwestCorner
            let southCorner = TileCoordinate(x: tileCoordinate.x, y: tileCoordinate.y + 1, z: tileCoordinate.z).northwestCorner
            let lonSpan = eastCorner.longitude - corner.longitude
            let latSpan = corner.latitude - southCorner.latitude
            cellSizeLon = lonSpan / Double(width)
            cellSizeLat = latSpan / Double(height)
        }
        
        // Parse elevation data
        let elevations = try parseElevationData(from: cgImage)
        
        guard elevations.count == width * height else {
            throw DEMLoaderError.invalidDataSize
        }
        
        return DEMTile(
            width: width,
            height: height,
            cellSizeLon: cellSizeLon,
            cellSizeLat: cellSizeLat,
            originLatitude: corner.latitude,
            originLongitude: corner.longitude,
            elevations: elevations,
            tileCoordinate: tileCoordinate
        )
    }
    
    /// Parse elevation data from a CGImage
    /// - Parameter image: The CGImage containing elevation data
    /// - Returns: Array of elevation values in meters
    private func parseElevationData(from image: CGImage) throws -> [Float] {
        let width = image.width
        let height = image.height
        let totalPixels = width * height
        
        // USGS 3DEP tiles are typically 32-bit float grayscale
        // We'll try to read them as such
        
        // Check bits per component
        let bitsPerComponent = image.bitsPerComponent
        let bitsPerPixel = image.bitsPerPixel
        
        // Create a buffer to hold the raw pixel data
        var elevations: [Float] = []
        elevations.reserveCapacity(totalPixels)
        
        // Try to read as 32-bit float (most common for USGS tiles)
        if bitsPerComponent == 32 && bitsPerPixel == 32 {
            elevations = try parseFloat32Image(image)
        }
        // Try 16-bit integer (some tiles use this)
        else if bitsPerComponent == 16 {
            elevations = try parseInt16Image(image)
        }
        // Try 8-bit (less common but possible)
        else if bitsPerComponent == 8 {
            elevations = try parseInt8Image(image)
        }
        else {
            // Fallback: try to read as any format and convert
            elevations = try parseGenericImage(image)
        }
        
        return elevations
    }
    
    /// Parse 32-bit float grayscale image
    private func parseFloat32Image(_ image: CGImage) throws -> [Float] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4 // 4 bytes per float
        
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw DEMLoaderError.failedToReadPixelData
        }
        
        var elevations: [Float] = []
        elevations.reserveCapacity(width * height)
        
        // Read float values
        bytes.withMemoryRebound(to: Float.self, capacity: width * height) { floatPtr in
            for i in 0..<(width * height) {
                elevations.append(floatPtr[i])
            }
        }
        
        return elevations
    }
    
    /// Parse 16-bit integer grayscale image
    private func parseInt16Image(_ image: CGImage) throws -> [Float] {
        let width = image.width
        let height = image.height
        
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw DEMLoaderError.failedToReadPixelData
        }
        
        var elevations: [Float] = []
        elevations.reserveCapacity(width * height)
        
        // Read 16-bit values and convert to float
        bytes.withMemoryRebound(to: UInt16.self, capacity: width * height) { uint16Ptr in
            for i in 0..<(width * height) {
                // Convert to signed int and then to float (elevation in meters)
                let value = Int16(bitPattern: uint16Ptr[i])
                elevations.append(Float(value))
            }
        }
        
        return elevations
    }
    
    /// Parse 8-bit grayscale image
    private func parseInt8Image(_ image: CGImage) throws -> [Float] {
        let width = image.width
        let height = image.height
        
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw DEMLoaderError.failedToReadPixelData
        }
        
        var elevations: [Float] = []
        elevations.reserveCapacity(width * height)
        
        // Read 8-bit values and convert to float
        for i in 0..<(width * height) {
            elevations.append(Float(bytes[i]))
        }
        
        return elevations
    }
    
    /// Generic image parser - creates a temporary context and reads pixels
    private func parseGenericImage(_ image: CGImage) throws -> [Float] {
        let width = image.width
        let height = image.height
        
        // Create a grayscale context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerPixel = 4 // Use 4 bytes per pixel for float
        let bytesPerRow = bytesPerPixel * width
        let bitmapInfo = CGImageAlphaInfo.none.rawValue | CGBitmapInfo.floatComponents.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw DEMLoaderError.failedToCreateContext
        }
        
        // Draw the image into the context
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            throw DEMLoaderError.failedToReadPixelData
        }
        
        var elevations: [Float] = []
        elevations.reserveCapacity(width * height)
        
        // Read float values
        data.assumingMemoryBound(to: Float.self).withMemoryRebound(to: Float.self, capacity: width * height) { floatPtr in
            for i in 0..<(width * height) {
                elevations.append(floatPtr[i])
            }
        }
        
        return elevations
    }
}

// MARK: - Errors

enum DEMLoaderError: LocalizedError {
    case failedToLoadImage
    case invalidDataSize
    case failedToReadPixelData
    case failedToCreateContext
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .failedToLoadImage:
            return "Failed to load GeoTIFF image"
        case .invalidDataSize:
            return "Invalid DEM data size"
        case .failedToReadPixelData:
            return "Failed to read pixel data from image"
        case .failedToCreateContext:
            return "Failed to create graphics context"
        case .unsupportedFormat:
            return "Unsupported GeoTIFF format"
        }
    }
}
