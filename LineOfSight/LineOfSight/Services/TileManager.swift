//
//  TileManager.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/21/25.
//

import Foundation
import CoreLocation

/// Manages downloading, caching, and loading of DEM tiles
actor TileManager {
    
    // MARK: - Properties
    
    /// In-memory cache of loaded tiles
    private var tileCache: [TileCoordinate: DEMTile] = [:]
    
    /// Maximum number of tiles to keep in memory
    private let maxCacheSize = 20
    
    /// Cache directory for DEM tiles
    private let cacheDirectory: URL
    
    /// URLSession for downloading tiles
    private let urlSession: URLSession
    
    /// Track ongoing downloads to prevent duplicate requests
    private var activeDownloads: [TileCoordinate: Task<DEMTile, Error>] = [:]
    
    /// DEMLoader for parsing GeoTIFF files
    private let loader = DEMLoader()
    
    // MARK: - Initialization
    
    init() {
        // Set up cache directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = appSupport.appendingPathComponent("DEMCache", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure URLSession for downloading
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Load a tile for the given coordinate
    /// - Parameter coordinate: Geographic coordinate within the desired tile
    /// - Returns: The loaded DEM tile
    func loadTile(for coordinate: CLLocationCoordinate2D) async throws -> DEMTile {
        let tileCoord = TileCoordinate(from: coordinate)
        return try await loadTile(tileCoordinate: tileCoord)
    }
    
    /// Load a tile by its tile coordinate
    /// - Parameter tileCoordinate: The tile coordinate
    /// - Returns: The loaded DEM tile
    func loadTile(tileCoordinate: TileCoordinate) async throws -> DEMTile {
        // Check memory cache first
        if let cached = tileCache[tileCoordinate] {
            return cached
        }
        
        // Check if there's already an active download for this tile
        if let downloadTask = activeDownloads[tileCoordinate] {
            return try await downloadTask.value
        }
        
        // Create a new download/load task
        let task = Task<DEMTile, Error> {
            // Check disk cache
            if let tile = try await loadFromDisk(tileCoordinate: tileCoordinate) {
                cacheTile(tile)
                return tile
            }
            
            // Download if not in disk cache
            let tile = try await downloadTile(tileCoordinate: tileCoordinate)
            cacheTile(tile)
            return tile
        }
        
        activeDownloads[tileCoordinate] = task
        
        do {
            let tile = try await task.value
            activeDownloads.removeValue(forKey: tileCoordinate)
            return tile
        } catch {
            activeDownloads.removeValue(forKey: tileCoordinate)
            throw error
        }
    }
    
    /// Preload tiles for a given area
    /// - Parameters:
    ///   - center: Center coordinate
    ///   - radiusKm: Radius in kilometers around the center
    func preloadTiles(around center: CLLocationCoordinate2D, radiusKm: Double) async {
        // For Web Mercator tiles at zoom 14, calculate the number of tiles to preload
        // At zoom 14, each tile is roughly 10km x 10km at mid-latitudes
        let tileRange = Int(ceil(radiusKm / 10.0))
        
        // Get center tile coordinates
        let centerTile = TileCoordinate(from: center)
        
        // Load surrounding tiles
        for xOffset in -tileRange...tileRange {
            for yOffset in -tileRange...tileRange {
                let tileCoord = TileCoordinate(
                    x: centerTile.x + xOffset,
                    y: centerTile.y + yOffset,
                    z: centerTile.z
                )
                
                // Load each tile, ignoring errors
                _ = try? await loadTile(tileCoordinate: tileCoord)
            }
        }
    }
    
    /// Clear all cached tiles from memory
    func clearMemoryCache() {
        tileCache.removeAll()
    }
    
    /// Clear all cached tiles from disk
    func clearDiskCache() throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        
        for url in contents {
            try fileManager.removeItem(at: url)
        }
        
        tileCache.removeAll()
    }
    
    /// Get the size of the disk cache in bytes
    func cacheSize() throws -> Int64 {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
        
        var totalSize: Int64 = 0
        for url in contents {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            totalSize += Int64(resources.fileSize ?? 0)
        }
        
        return totalSize
    }
    
    // MARK: - Private Methods
    
    /// Load a tile from disk cache
    private func loadFromDisk(tileCoordinate: TileCoordinate) async throws -> DEMTile? {
        let fileURL = cacheDirectory.appendingPathComponent(tileCoordinate.filename)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        return try await loader.loadDEMTile(from: fileURL, tileCoordinate: tileCoordinate)
    }
    
    /// Download a tile from USGS AWS S3
    private func downloadTile(tileCoordinate: TileCoordinate) async throws -> DEMTile {
        let url = tileCoordinate.url
        let destinationURL = cacheDirectory.appendingPathComponent(tileCoordinate.filename)
        
        // Download the file
        let (tempURL, response) = try await urlSession.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TileManagerError.downloadFailed(tileCoordinate: tileCoordinate)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TileManagerError.downloadFailed(tileCoordinate: tileCoordinate)
        }
        
        // Move to cache directory
        try? FileManager.default.removeItem(at: destinationURL) // Remove if exists
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        // Load and return the tile
        return try await loader.loadDEMTile(from: destinationURL, tileCoordinate: tileCoordinate)
    }
    
    /// Cache a tile in memory
    private func cacheTile(_ tile: DEMTile) {
        tileCache[tile.tileCoordinate] = tile
        
        // Implement simple LRU by removing oldest entries if cache is too large
        if tileCache.count > maxCacheSize {
            // Remove the first (oldest) entry
            if let firstKey = tileCache.keys.first {
                tileCache.removeValue(forKey: firstKey)
            }
        }
    }
}

// MARK: - Errors

enum TileManagerError: LocalizedError {
    case downloadFailed(tileCoordinate: TileCoordinate)
    case tileNotAvailable(tileCoordinate: TileCoordinate)
    case invalidTileData
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let coord):
            return "Failed to download DEM tile: \(coord.filename)"
        case .tileNotAvailable(let coord):
            return "DEM tile not available: \(coord.filename)"
        case .invalidTileData:
            return "Invalid DEM tile data"
        }
    }
}
