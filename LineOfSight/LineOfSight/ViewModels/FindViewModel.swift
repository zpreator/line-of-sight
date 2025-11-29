//
//  FindViewModel.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import Foundation
import CoreLocation
import Combine
import MapKit

/// ViewModel for the Find functionality
@MainActor
class FindViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var selectedLocation: Location?
    @Published var currentUserLocation: CLLocation?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to San Francisco
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @Published var selectedCelestialObject: CelestialObject = .sun
    @Published var targetDate = Date()
    @Published var minuteIntersections: [MinuteIntersection] = []
    @Published var calculationState: CalculationState?
    @Published var showCalculationSheet = false
    
    // MARK: - Private Properties
    private let locationService: LocationService
    private let demService = DEMService()
    private let sunPathService = SunPathService()
    private let terrainIntersector = TerrainIntersector()
    private var cancellables = Set<AnyCancellable>()
    private weak var calculationStore: CalculationStore?
    
    @Published var showSaveDialog = false
    @Published var saveName = ""
    
    // MARK: - Initialization
    init(locationService: LocationService? = nil, calculationStore: CalculationStore? = nil) {
        self.locationService = locationService ?? LocationService()
        self.calculationStore = calculationStore
        setupLocationObserver()
        requestLocationPermission()
    }
    
    // MARK: - Public Methods
    
    /// Request location permission and start location updates
    func requestLocationPermission() {
        locationService.requestLocationPermission()
        locationService.startLocationUpdates()
    }
    
    /// Handle map tap to select a location
    func selectLocation(at coordinate: CLLocationCoordinate2D, name: String? = nil) {
        isLoading = true
        errorMessage = nil
        
        Task {
            // Get elevation from DEM service (terrain-aware)
            // This will download DEM tiles if not cached
            let elevation = await demService.elevation(at: coordinate)
            
            let location = Location(
                name: name,
                coordinate: coordinate,
                elevation: elevation ?? 0,
                source: .map,
                precision: .approximate
            )
            
            await MainActor.run {
                self.selectedLocation = location
                self.isLoading = false
                
                // Show message if elevation data wasn't available
                if elevation == nil {
                    self.errorMessage = "Elevation data unavailable for this location. Downloading terrain data..."
                }
            }
        }
    }
    
    /// Clear the currently selected location
    func clearSelectedLocation() {
        selectedLocation = nil
        errorMessage = nil
    }
    
    /// Center map on user's current location
    func centerOnUserLocation() {
        // First try to use the cached location
        if let userLocation = currentUserLocation {
            mapRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            return
        }
        
        // If no cached location, try to get it from the location service directly
        if let serviceLocation = locationService.currentLocation {
            currentUserLocation = serviceLocation
            mapRegion = MKCoordinateRegion(
                center: serviceLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            return
        }
        
        // If still no location, fetch it asynchronously
        Task {
            do {
                errorMessage = "Getting your location..."
                let location = try await locationService.getCurrentLocation()
                currentUserLocation = location
                mapRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                errorMessage = nil
            } catch {
                errorMessage = "Error getting your location: \(error.localizedDescription)"
            }
        }
    }
    
    /// Calculate terrain-aware sun alignment path
    func calculateTerrainAlignment() async -> [SunAlignmentPoint] {
        guard let location = selectedLocation,
              selectedCelestialObject.type == .sun else { return [] }
        
        isLoading = true
        errorMessage = nil
        
        let alignmentPoints = await sunPathService.computeSunAlignmentPath(
            poi: location.coordinate,
            date: targetDate
        )
        
        await MainActor.run {
            self.isLoading = false
        }
        
        return alignmentPoints
    }
    
    /// Calculate optimal photographer positions for the current selection
    func calculatePhotographerPositions(hours: [Int]? = nil) async -> [PhotographerPosition] {
        guard let location = selectedLocation,
              selectedCelestialObject.type == .sun else { return [] }
        
        isLoading = true
        errorMessage = nil
        
        let positions = await sunPathService.computePhotographerPositions(
            poi: location.coordinate,
            date: targetDate,
            hours: hours
        )
        
        await MainActor.run {
            self.isLoading = false
        }
        
        return positions
    }
    
    /// Calculate per-minute ray-terrain intersections for the entire day
    /// Uses concurrent processing with TaskGroup for optimal performance
    /// Pre-calculates all sun positions to minimize SwiftAA calls
    func calculateMinuteIntersections() async {
        guard let location = selectedLocation else { return }
        
        isLoading = true
        errorMessage = nil
        showCalculationSheet = true
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: targetDate)
        
        // Step 1: Pre-calculate all sun positions
        calculationState = .calculating(CalculationProgress(
            currentStep: .preparingSunPositions,
            sunPositionsCalculated: 0,
            totalSunPositions: 1440,
            intersectionsFound: 0,
            totalIntersectionsProcessed: 0
        ))
        
        var sunPositions: [(minute: Int, date: Date, azimuth: Double, elevation: Double)] = []
        
        for minute in 0..<1440 {
            let eventDate = startDate.addingTimeInterval(TimeInterval(minute * 60))
            let sunPosition = AstronomicalCalculations.position(
                for: selectedCelestialObject,
                at: eventDate,
                coordinate: location.coordinate
            )
            
            // Update progress every 100 minutes
            if minute % 100 == 0 {
                calculationState = .calculating(CalculationProgress(
                    currentStep: .preparingSunPositions,
                    sunPositionsCalculated: minute,
                    totalSunPositions: 1440,
                    intersectionsFound: 0,
                    totalIntersectionsProcessed: 0
                ))
            }
            
            // Only include times when sun is above horizon with minimum elevation
            let minimumSunElevation = 2.0  // degrees
            if sunPosition.elevation > minimumSunElevation {
                sunPositions.append((
                    minute: minute,
                    date: eventDate,
                    azimuth: sunPosition.azimuth,
                    elevation: sunPosition.elevation
                ))
            }
        }
        
        // Step 2: Process ray intersections concurrently
        calculationState = .calculating(CalculationProgress(
            currentStep: .calculatingIntersections,
            sunPositionsCalculated: 1440,
            totalSunPositions: 1440,
            intersectionsFound: 0,
            totalIntersectionsProcessed: 0
        ))
        
        let intersections = await withTaskGroup(of: (MinuteIntersection?, Int).self, returning: [MinuteIntersection].self) { group in
            var processedCount = 0
            var foundCount = 0
            
            // Add tasks for each valid sun position
            for (index, sunPos) in sunPositions.enumerated() {
                group.addTask {
                    // Convert sun direction to ENU
                    let sunDirectionENU = CoordinateUtils.azAltToENU(
                        azimuth: sunPos.azimuth,
                        altitude: sunPos.elevation
                    )
                    
                    // Ray direction: from sun through POI (negate sun direction)
                    let rayDirection = -sunDirectionENU
                    
                    // Find intersection using optimized ray marching
                    if let intersectionCoord = await self.terrainIntersector.intersectRay(
                        from: location.coordinate,
                        poiElevation: location.elevation,
                        directionENU: rayDirection,
                        maxDistanceMeters: 50_000.0
                    ) {
                        let distance = location.coordinate.distance(to: intersectionCoord)
                        
                        return (MinuteIntersection(
                            minute: sunPos.minute,
                            time: sunPos.date,
                            coordinate: intersectionCoord,
                            sunAzimuth: sunPos.azimuth,
                            sunElevation: sunPos.elevation,
                            distance: distance
                        ), index)
                    }
                    
                    return (nil, index)
                }
            }
            
            // Collect results and update progress
            var results: [MinuteIntersection] = []
            for await (intersection, index) in group {
                processedCount += 1
                if intersection != nil {
                    foundCount += 1
                    results.append(intersection!)
                }
                
                // Update progress every 10 intersections
                if processedCount % 10 == 0 {
                    await MainActor.run {
                        self.calculationState = .calculating(CalculationProgress(
                            currentStep: .calculatingIntersections,
                            sunPositionsCalculated: 1440,
                            totalSunPositions: 1440,
                            intersectionsFound: foundCount,
                            totalIntersectionsProcessed: processedCount
                        ))
                    }
                }
            }
            
            // Sort by minute
            return results.sorted { $0.minute < $1.minute }
        }
        
        // Step 3: Finalize
        calculationState = .calculating(CalculationProgress(
            currentStep: .finishing,
            sunPositionsCalculated: 1440,
            totalSunPositions: 1440,
            intersectionsFound: intersections.count,
            totalIntersectionsProcessed: sunPositions.count
        ))
        
        // Brief delay to show finishing state
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await MainActor.run {
            self.minuteIntersections = intersections
            self.isLoading = false
            
            // Calculate summary
            if !intersections.isEmpty {
                let distances = intersections.map { $0.distance }
                let avgDistance = distances.reduce(0, +) / Double(distances.count)
                let minDistance = distances.min() ?? 0
                let maxDistance = distances.max() ?? 0
                
                let times = intersections.map { $0.time }
                let timeRange = times.min()!...times.max()!
                
                self.calculationState = .completed(CalculationSummary(
                    poiName: location.name ?? "Selected Location",
                    date: targetDate,
                    celestialObject: selectedCelestialObject,
                    totalIntersections: intersections.count,
                    timeRange: timeRange,
                    averageDistance: avgDistance,
                    closestDistance: minDistance,
                    farthestDistance: maxDistance
                ))
            } else {
                self.calculationState = .completed(CalculationSummary(
                    poiName: location.name ?? "Selected Location",
                    date: targetDate,
                    celestialObject: selectedCelestialObject,
                    totalIntersections: 0,
                    timeRange: nil,
                    averageDistance: 0,
                    closestDistance: 0,
                    farthestDistance: 0
                ))
            }
        }
    }
    
    // MARK: - Sheet Control Methods
    
    /// Dismiss the calculation sheet
    func dismissCalculationSheet() {
        showCalculationSheet = false
        // Keep calculationState so results can be shown again
    }
    
    /// View results after calculation
    func viewCalculationResults() {
        showCalculationSheet = false
        // Results are already on the map
    }
    
    /// Save calculation to history
    func saveCalculation() {
        guard let location = selectedLocation,
              !minuteIntersections.isEmpty,
              let store = calculationStore else {
            showCalculationSheet = false
            return
        }
        
        // Set default name
        saveName = location.name ?? "Saved Location"
        showSaveDialog = true
    }
    
    /// Complete the save with the provided name
    func completeSave() {
        guard let location = selectedLocation,
              !minuteIntersections.isEmpty,
              let store = calculationStore,
              !saveName.isEmpty else {
            return
        }
        
        store.saveCalculation(
            name: saveName,
            landmark: location,
            celestialObject: selectedCelestialObject,
            targetDate: targetDate,
            intersections: minuteIntersections
        )
        
        showSaveDialog = false
        showCalculationSheet = false
    }
    
    /// Load a saved calculation into the view
    func loadSavedCalculation(_ calculation: SavedCalculation) {
        // Restore the location
        selectedLocation = calculation.landmark
        
        // Restore celestial object and date
        selectedCelestialObject = calculation.celestialObject
        targetDate = calculation.targetDate
        
        // Restore minute intersections from saved data
        minuteIntersections = calculation.intersections.map { saved in
            MinuteIntersection(
                minute: saved.minute,
                time: saved.time,
                coordinate: CLLocationCoordinate2D(
                    latitude: saved.latitude,
                    longitude: saved.longitude
                ),
                sunAzimuth: saved.sunAzimuth,
                sunElevation: saved.sunElevation,
                distance: saved.distance
            )
        }
        
        // Center map on the location
        mapRegion = MKCoordinateRegion(
            center: calculation.landmark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        
        // Show completed state
        calculationState = .completed(CalculationSummary(
            poiName: calculation.landmark.name ?? "Saved Location",
            date: calculation.targetDate,
            celestialObject: calculation.celestialObject,
            totalIntersections: calculation.summary.totalIntersections,
            timeRange: calculation.intersections.isEmpty ? nil : calculation.intersections.first!.time...calculation.intersections.last!.time,
            averageDistance: calculation.summary.averageDistance,
            closestDistance: calculation.summary.closestDistance,
            farthestDistance: calculation.summary.farthestDistance
        ))
    }
    
    /// Find the best alignment time for the current selection
    func findBestAlignmentTime(preferredAzimuth: Double? = nil) async -> SunAlignmentPoint? {
        guard let location = selectedLocation,
              selectedCelestialObject.type == .sun else { return nil }
        
        return await sunPathService.findBestAlignmentTime(
            poi: location.coordinate,
            date: targetDate,
            preferredAzimuth: preferredAzimuth
        )
    }
    
    /// Get formatted coordinate string for display
    func formattedCoordinates(for coordinate: CLLocationCoordinate2D) -> String {
        let latitude = String(format: "%.6f", coordinate.latitude)
        let longitude = String(format: "%.6f", coordinate.longitude)
        return "\(latitude), \(longitude)"
    }
    
    /// Get distance from user to selected location
    func distanceToSelectedLocation() -> String? {
        guard let selectedLocation = selectedLocation,
              let userLocation = currentUserLocation else { return nil }
        
        let distance = locationService.distance(
            from: userLocation.coordinate,
            to: selectedLocation.coordinate
        )
        
        if distance < 1000 {
            return String(format: "%.0fm", distance)
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupLocationObserver() {
        locationService.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.currentUserLocation = location
                
                // Update map region to user location on first update
                if let location = location, self?.mapRegion.center.latitude == 37.7749 {
                    self?.mapRegion = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                }
            }
            .store(in: &cancellables)
        
        locationService.$locationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error?.localizedDescription
            }
            .store(in: &cancellables)
    }
    
}

// Removed unused function calculateAlignment and its dependencies

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}

// MARK: - Supporting Data Models

struct AlignmentCalculation: Identifiable {
    let id: UUID
    let name: String
    let landmark: Location
    let celestialObject: CelestialObject
    let calculationDate: Date
    let targetDate: Date
    let alignmentEvents: [AlignmentEvent]
    let projectionPoints: ProjectionPoints // Two ground projection points
}

struct ProjectionPoints {
    let poiProjection: CLLocationCoordinate2D // Where POI projects down to ground
    let celestialProjection: CLLocationCoordinate2D // Where celestial object projects down through POI
}

struct AlignmentEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let azimuth: Double
    let elevation: Double
    let photographerPosition: CLLocationCoordinate2D
    let alignmentQuality: Double
    let distance: Double // Distance from photographer to landmark
}

struct MinuteIntersection: Identifiable {
    let id = UUID()
    let minute: Int  // Minute of the day (0-1439)
    let time: Date
    let coordinate: CLLocationCoordinate2D
    let sunAzimuth: Double
    let sunElevation: Double
    let distance: Double
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }
    
    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }
}