//
//  MapSelectionView.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Calculation Mode

enum CalculationMode: String, CaseIterable {
    case alignment = "Alignment"
    case horizon = "Horizon"
    
    var icon: String {
        switch self {
        case .alignment:
            return "scope"
        case .horizon:
            return "sunrise.fill"
        }
    }
    
    var description: String {
        switch self {
        case .alignment:
            return "Find where the sun aligns with a target"
        case .horizon:
            return "Find when the sun rises/sets over terrain"
        }
    }
    
    var mapPrompt: String {
        switch self {
        case .alignment:
            return "Tap map to select target location"
        case .horizon:
            return "Tap map to set observation point"
        }
    }
    
    var calculateButtonLabel: String {
        switch self {
        case .alignment:
            return "Calculate"
        case .horizon:
            return "Find Rise/Set"
        }
    }
}

struct MapSelectionView: View {
    let calculationStore: CalculationStore
    @Binding var selectedTab: Int
    @StateObject private var viewModel: FindViewModel
    @State private var showingCelestialObjectPicker = false
    @State private var showingDatePicker = false
    @State private var isSearching = false
    @State private var hasResults = false
    @State private var mapType: MKMapType = .standard
    @State private var calculationMode: CalculationMode = .alignment
    
    init(calculationStore: CalculationStore, selectedTab: Binding<Int>) {
        self.calculationStore = calculationStore
        self._selectedTab = selectedTab
        self._viewModel = StateObject(wrappedValue: FindViewModel(calculationStore: calculationStore))
    }
    
    var body: some View {
        ZStack {
            // Main Map View
            InteractiveMapView(
                region: $viewModel.mapRegion,
                selectedLocation: viewModel.selectedLocation,
                minuteIntersections: viewModel.minuteIntersections,
                hasResults: hasResults,
                mapType: $mapType,
                calculationMode: calculationMode,
                onLocationSelected: { coordinate in
                    viewModel.selectLocation(at: coordinate)
                }
            )
            .ignoresSafeArea()
            
            // Overlay Controls
            VStack(alignment: .leading) {
                // Mode Picker
                if !hasResults {
                    Picker("Mode", selection: $calculationMode) {
                        ForEach(CalculationMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 60)
                    .onChange(of: calculationMode) { _ in
                        // Clear selection when switching modes
                        if viewModel.selectedLocation != nil && !hasResults {
                            viewModel.selectedLocation = nil
                        }
                    }
                }
                
                // Search Bar or Compact Top Control Bar
                if isSearching {
                    LocationSearchBar(
                        isSearching: $isSearching,
                        regionBias: viewModel.mapRegion
                    ) { mapItem in
                        handleSearchSelection(mapItem)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    // Compact horizontal toolbar
                    HStack(spacing: 8) {
                        // Search Button
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                isSearching = true
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.body)
                                if viewModel.selectedLocation == nil {
                                    Text("Search")
                                        .font(.subheadline)
                                }
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(hasResults)
                        .opacity(hasResults ? 0.5 : 1.0)
                        
                        // Use Current Location Button (only in horizon mode)
                        if calculationMode == .horizon {
                            Button(action: {
                                viewModel.centerOnUserLocation()
                                if let userLocation = viewModel.currentUserLocation {
                                    viewModel.selectLocation(
                                        at: userLocation.coordinate,
                                        name: "Current Location"
                                    )
                                }
                            }) {
                                Image(systemName: "location.fill")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(hasResults)
                            .opacity(hasResults ? 0.5 : 1.0)
                        }
                        
                        // Celestial Object Dropdown
                        Button(action: { showingCelestialObjectPicker = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.selectedCelestialObject.type.icon)
                                    .font(.body)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(hasResults)
                        .opacity(hasResults ? 0.5 : 1.0)
                        
                        // Date Dropdown
                        Button(action: { showingDatePicker = true }) {
                            HStack(spacing: 4) {
                                Text(formatCompactDate(viewModel.targetDate))
                                    .font(.subheadline)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(hasResults)
                        .opacity(hasResults ? 0.5 : 1.0)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // New Calculation Button (when results exist)
                if hasResults {
                    Button(action: {
                        clearResults()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                            Text("New")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.top, 8)
                }
                
                Spacer()
                
                // Bottom Action Buttons (centered)
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // Calculate Button (when location selected but no results)
                        if viewModel.selectedLocation != nil && !hasResults {
                            Button(action: {
                                Task {
                                    // Call appropriate calculation based on mode
                                    if calculationMode == .horizon {
                                        await viewModel.calculateHorizonEvents()
                                    } else {
                                        await viewModel.calculateMinuteIntersections()
                                    }
                                    hasResults = true
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: calculationMode.icon)
                                    Text(calculationMode.calculateButtonLabel)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.accentColor, in: Capsule())
                            }
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                        
                        // Show Results Button (when results available)
                        if hasResults && !viewModel.showCalculationSheet {
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.showCalculationSheet = true
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "chart.bar.fill")
                                    Text("Results")
                                    // Only show count in alignment mode
                                    if calculationMode == .alignment && !viewModel.minuteIntersections.isEmpty {
                                        Text("(\(viewModel.minuteIntersections.count))")
                                            .font(.caption)
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.accentColor, in: Capsule())
                            }
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 20)
            }
            .padding()
            
            // Floating Map Controls - Bottom Right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    MapControlMenu(
                        mapType: $mapType,
                        onLocationTap: viewModel.centerOnUserLocation
                    )
                    .padding(.trailing)
                    .padding(.bottom, 20)
                }
            }
            
            // Calculation Progress Sheet
            if viewModel.showCalculationSheet, let state = viewModel.calculationState {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        
                        // Show different sheet based on calculation mode
                        if calculationMode == .horizon {
                            // Horizon Results Sheet with real data
                            HorizonResultsSheet(
                                observerLocation: viewModel.selectedLocation?.name ?? "Selected Location",
                                date: viewModel.targetDate,
                                celestialObject: viewModel.selectedCelestialObject,
                                events: viewModel.horizonEvents.map { detail in
                                    // Map HorizonEventType to HorizonEvent.EventType
                                    let eventType: HorizonEvent.EventType
                                    switch detail.type {
                                    case .rise:
                                        eventType = .rise
                                    case .set:
                                        eventType = .set
                                    }
                                    
                                    return HorizonEvent(
                                        type: eventType,
                                        time: detail.time,
                                        azimuth: detail.azimuth,
                                        terrainElevation: detail.terrainElevation,
                                        distance: detail.distance
                                    )
                                },
                                onViewResults: {
                                    viewModel.viewCalculationResults()
                                },
                                onSave: {
                                    viewModel.saveCalculation()
                                },
                                onDismiss: {
                                    viewModel.dismissCalculationSheet()
                                }
                            )
                            .padding(.bottom, geometry.safeAreaInsets.bottom)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            // Original Alignment Results Sheet
                            CalculationProgressSheet(
                                state: state,
                                onDismiss: {
                                    viewModel.dismissCalculationSheet()
                                },
                                onViewResults: {
                                    viewModel.viewCalculationResults()
                                },
                                onSave: {
                                    viewModel.saveCalculation()
                                }
                            )
                            .padding(.bottom, geometry.safeAreaInsets.bottom)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.dismissCalculationSheet()
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showCalculationSheet)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showingCelestialObjectPicker) {
            CelestialObjectPicker(selectedObject: $viewModel.selectedCelestialObject)
        }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerView(selectedDate: $viewModel.targetDate)
        }
        .sheet(isPresented: $viewModel.showSaveDialog) {
            NavigationView {
                VStack(spacing: 20) {
                    Text("Save Calculation")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    TextField("Name this location", text: $viewModel.saveName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    Spacer()
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            viewModel.showSaveDialog = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            viewModel.completeSave()
                        }
                        .disabled(viewModel.saveName.isEmpty)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Check if we need to load a saved calculation
            if let loadId = calculationStore.loadedCalculationId,
               let calculation = calculationStore.savedCalculations.first(where: { $0.id == loadId }) {
                viewModel.loadSavedCalculation(calculation)
                hasResults = true
                calculationStore.loadedCalculationId = nil // Clear the flag
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Handle selection from search results
    private func handleSearchSelection(_ mapItem: MKMapItem) {
        // Center map on selected location
        viewModel.mapRegion = MKCoordinateRegion(
            center: mapItem.placemark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        // Select the location
        viewModel.selectLocation(
            at: mapItem.placemark.coordinate,
            name: mapItem.name
        )
        
        // Reset results state when new location selected
        hasResults = false
    }
    
    /// Format date in compact format (e.g., "11/28/25")
    private func formatCompactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        return formatter.string(from: date)
    }
    
    /// Clear all results and allow new location selection
    private func clearResults() {
        withAnimation(.spring(response: 0.3)) {
            hasResults = false
            viewModel.minuteIntersections = []
            viewModel.selectedLocation = nil
            viewModel.calculationState = nil
            viewModel.showCalculationSheet = false
        }
    }
    
}

// MARK: - Interactive Map View

struct InteractiveMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let selectedLocation: Location?
    let minuteIntersections: [MinuteIntersection]
    let hasResults: Bool
    @Binding var mapType: MKMapType
    let calculationMode: CalculationMode
    let onLocationSelected: (CLLocationCoordinate2D) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.showsCompass = true
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        mapView.addGestureRecognizer(tapGesture)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update coordinator's hasResults flag
        context.coordinator.hasResults = hasResults
        
        // Update map type if needed
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }
        
        // Update region if needed
        if !mapView.region.isEqual(to: region, tolerance: 0.001) {
            mapView.setRegion(region, animated: true)
        }
        
        // Update annotations
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        
        if let location = selectedLocation {
            let annotation = LocationAnnotation(location: location)
            mapView.addAnnotation(annotation)
        }
        
        // Add minute intersection annotations
        for intersection in minuteIntersections {
            let annotation = MinuteIntersectionAnnotation(intersection: intersection)
            mapView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: InteractiveMapView
        var hasResults: Bool = false
        
        init(_ parent: InteractiveMapView) {
            self.parent = parent
            self.hasResults = parent.hasResults
        }
        
        var calculationMode: CalculationMode {
            return parent.calculationMode
        }
        
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            // Don't allow new location selection if results exist
            guard !hasResults else { return }
            
            let mapView = gesture.view as! MKMapView
            let touchPoint = gesture.location(in: mapView)
            let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
            
            // Call the callback with the tapped coordinate
            parent.onLocationSelected(coordinate)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Update the binding when the user pans/zooms
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // User location annotation
            if annotation is MKUserLocation {
                return nil
            }
            
            // Minute intersection annotations
            if let intersectionAnnotation = annotation as? MinuteIntersectionAnnotation {
                let identifier = "IntersectionPin"
                let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                
                annotationView.annotation = annotation
                annotationView.markerTintColor = .systemBlue
                // Show hour:minute instead of just hour
                let hour = intersectionAnnotation.intersection.minute / 60
                let minute = intersectionAnnotation.intersection.minute % 60
                annotationView.glyphText = String(format: "%d:%02d", hour, minute)
                annotationView.canShowCallout = true
                annotationView.displayPriority = .defaultLow
                
                // Add detail disclosure button for navigation options
                let button = UIButton(type: .detailDisclosure)
                annotationView.rightCalloutAccessoryView = button
                
                return annotationView
            }
            
            // Location annotation (POI)
            if annotation is LocationAnnotation {
                let identifier = "LocationPin"
                let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                
                annotationView.annotation = annotation
                
                // Different styling based on calculation mode
                switch calculationMode {
                case .alignment:
                    annotationView.markerTintColor = .red
                    annotationView.glyphImage = UIImage(systemName: "mappin")
                case .horizon:
                    annotationView.markerTintColor = .systemBlue
                    annotationView.glyphImage = UIImage(systemName: "eye.fill")
                }
                
                annotationView.canShowCallout = true
                annotationView.displayPriority = .required
                
                return annotationView
            }
            
            return nil
        }
        
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let intersectionAnnotation = view.annotation as? MinuteIntersectionAnnotation else { return }
            
            // Show action sheet for the intersection point
            let coordinate = intersectionAnnotation.coordinate
            let actionSheet = UIAlertController(title: intersectionAnnotation.title, message: intersectionAnnotation.subtitle, preferredStyle: .actionSheet)
            
            // Open in Apple Maps
            actionSheet.addAction(UIAlertAction(title: "Open in Maps", style: .default) { _ in
                self.openInAppleMaps(coordinate: coordinate, title: intersectionAnnotation.title)
            })
            
            // Open in Google Maps
            actionSheet.addAction(UIAlertAction(title: "Open in Google Maps", style: .default) { _ in
                self.openInGoogleMaps(coordinate: coordinate)
            })
            
            // Copy Address
            actionSheet.addAction(UIAlertAction(title: "Copy Address", style: .default) { _ in
                self.copyAddress(coordinate: coordinate)
            })
            
            // Copy Coordinates
            actionSheet.addAction(UIAlertAction(title: "Copy Coordinates", style: .default) { _ in
                let coordinateString = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
                UIPasteboard.general.string = coordinateString
            })
            
            actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            // Present from the map view's window
            if let windowScene = mapView.window?.windowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                var topController = rootViewController
                while let presentedViewController = topController.presentedViewController {
                    topController = presentedViewController
                }
                
                // For iPad, set source view with proper positioning
                if let popover = actionSheet.popoverPresentationController {
                    // Use the map view as source to ensure proper positioning
                    popover.sourceView = mapView
                    
                    // Calculate a safe rect centered on the annotation but within the map bounds
                    // Convert annotation coordinate to map point
                    let annotationPoint = mapView.convert(intersectionAnnotation.coordinate, toPointTo: mapView)
                    
                    // Create a small rect around the annotation point
                    let rectSize: CGFloat = 40
                    var sourceRect = CGRect(
                        x: annotationPoint.x - rectSize / 2,
                        y: annotationPoint.y - rectSize / 2,
                        width: rectSize,
                        height: rectSize
                    )
                    
                    // Ensure the rect is within the map bounds to prevent off-screen popovers
                    let mapBounds = mapView.bounds
                    sourceRect.origin.x = max(rectSize, min(sourceRect.origin.x, mapBounds.width - rectSize * 2))
                    sourceRect.origin.y = max(rectSize, min(sourceRect.origin.y, mapBounds.height - rectSize * 2))
                    
                    popover.sourceRect = sourceRect
                    
                    // Allow UIKit to adjust the popover position automatically
                    popover.permittedArrowDirections = .any
                }
                
                topController.present(actionSheet, animated: true)
            }
        }
        
        private func openInAppleMaps(coordinate: CLLocationCoordinate2D, title: String?) {
            let placemark = MKPlacemark(coordinate: coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = title ?? "Location"
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        }
        
        private func openInGoogleMaps(coordinate: CLLocationCoordinate2D) {
            let googleMapsURL = URL(string: "comgooglemaps://?q=\(coordinate.latitude),\(coordinate.longitude)&center=\(coordinate.latitude),\(coordinate.longitude)&zoom=14")
            let webURL = URL(string: "https://www.google.com/maps?q=\(coordinate.latitude),\(coordinate.longitude)")
            
            if let googleMapsURL = googleMapsURL, UIApplication.shared.canOpenURL(googleMapsURL) {
                UIApplication.shared.open(googleMapsURL)
            } else if let webURL = webURL {
                UIApplication.shared.open(webURL)
            }
        }
        
        private func copyAddress(coordinate: CLLocationCoordinate2D) {
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let placemark = placemarks?.first {
                    var addressComponents: [String] = []
                    
                    if let name = placemark.name { addressComponents.append(name) }
                    if let thoroughfare = placemark.thoroughfare { addressComponents.append(thoroughfare) }
                    if let locality = placemark.locality { addressComponents.append(locality) }
                    if let administrativeArea = placemark.administrativeArea { addressComponents.append(administrativeArea) }
                    if let postalCode = placemark.postalCode { addressComponents.append(postalCode) }
                    if let country = placemark.country { addressComponents.append(country) }
                    
                    let address = addressComponents.isEmpty ? String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude) : addressComponents.joined(separator: ", ")
                    
                    DispatchQueue.main.async {
                        UIPasteboard.general.string = address
                    }
                } else {
                    // Fallback to coordinates if geocoding fails
                    let coordinateString = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
                    DispatchQueue.main.async {
                        UIPasteboard.general.string = coordinateString
                    }
                }
            }
        }
    }
}

// MARK: - Location Annotation

class LocationAnnotation: NSObject, MKAnnotation {
    let location: Location
    
    var coordinate: CLLocationCoordinate2D {
        return location.coordinate
    }
    
    var title: String? {
        return location.name ?? "Selected Location"
    }
    
    var subtitle: String? {
        return String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude)
    }
    
    init(location: Location) {
        self.location = location
    }
}

// MARK: - Minute Intersection Annotation

class MinuteIntersectionAnnotation: NSObject, MKAnnotation {
    let intersection: MinuteIntersection
    
    var coordinate: CLLocationCoordinate2D {
        return intersection.coordinate
    }
    
    var title: String? {
        return intersection.timeLabel
    }
    
    var subtitle: String? {
        let distanceStr = UnitFormatter.formatDistance(intersection.distance, useMetric: UnitFormatter.isMetric())
        return String(format: "Sun: %.1f° Az, %.1f° El • %@",
                     intersection.sunAzimuth,
                     intersection.sunElevation,
                     distanceStr)
    }
    
    init(intersection: MinuteIntersection) {
        self.intersection = intersection
    }
}

// MARK: - MKCoordinateRegion Extension

extension MKCoordinateRegion {
    func isEqual(to other: MKCoordinateRegion, tolerance: Double) -> Bool {
        return abs(center.latitude - other.center.latitude) < tolerance &&
               abs(center.longitude - other.center.longitude) < tolerance &&
               abs(span.latitudeDelta - other.span.latitudeDelta) < tolerance &&
               abs(span.longitudeDelta - other.span.longitudeDelta) < tolerance
    }
}

// MARK: - Supporting Views

struct LocationPin: View {
    let location: Location
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundColor(.red)
                .background(Circle().fill(.white))
            
            Image(systemName: "triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .offset(y: -5)
        }
    }
}

struct LocationInfoCard: View {
    let location: Location
    let viewModel: FindViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(location.name ?? "Selected Location")
                        .font(.headline)
                    
                    Text(viewModel.formattedCoordinates(for: location.coordinate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: viewModel.clearSelectedLocation) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(String(format: "%@ elevation (DEM)", UnitFormatter.formatElevation(location.elevation, useMetric: UnitFormatter.useMetersForElevation())), systemImage: "mountain.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let distance = viewModel.distanceToSelectedLocation() {
                        Label(distance, systemImage: "ruler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Data source note
                Text("⚠️ Elevation from Mapzen DEM tiles may differ from Apple Maps visual terrain")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 4) {
                    Image(systemName: location.source.icon)
                    Text(location.precision.displayName)
                    
                    if viewModel.isLoading {
                        Text("• Fetching elevation...")
                            .foregroundColor(.accentColor)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct LocationPromptCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text("Tap on the map to select a location")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CelestialObjectPicker: View {
    @Binding var selectedObject: CelestialObject
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(CelestialObject.defaultObjects, id: \.id) { object in
                HStack {
                    Image(systemName: object.type.icon)
                        .foregroundColor(colorForType(object.type))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading) {
                        Text(object.name)
                            .font(.headline)
                        
                        Text(object.type.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if object.id == selectedObject.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedObject = object
                    dismiss()
                }
            }
            .navigationTitle("Celestial Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func colorForType(_ type: CelestialType) -> Color {
        switch type {
        case .sun:
            return .yellow
        }
    }
}

struct DatePickerView: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CalculationResultsView: View {
    let calculation: AlignmentCalculation
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack {
                // Tab Picker
                Picker("View", selection: $selectedTab) {
                    Text("Timeline").tag(0)
                    Text("Best Times").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    TimelineView(calculation: calculation)
                        .tag(0)
                    
                    BestTimesView(calculation: calculation)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("\(calculation.celestialObject.name) Alignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Timeline View
struct TimelineView: View {
    let calculation: AlignmentCalculation
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary Card
                SummaryCard(calculation: calculation)
                
                // Timeline of alignment events
                VStack(alignment: .leading, spacing: 12) {
                    Text("24-Hour Timeline")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVStack(spacing: 8) {
                        ForEach(calculation.alignmentEvents.prefix(12)) { event in
                            TimelineEventCard(event: event, objectName: calculation.celestialObject.name)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - Best Times View
struct BestTimesView: View {
    let calculation: AlignmentCalculation
    
    var bestEvents: [AlignmentEvent] {
        calculation.alignmentEvents
            .filter { $0.alignmentQuality > 0.6 && $0.elevation > 0 }
            .sorted { $0.alignmentQuality > $1.alignmentQuality }
            .prefix(5)
            .map { $0 }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SummaryCard(calculation: calculation)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Best Alignment Times")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if bestEvents.isEmpty {
                        EmptyStateCard(
                            icon: "moon.stars",
                            title: "No Optimal Times Today",
                            description: "The \(calculation.celestialObject.name.lowercased()) won't have good alignment with your selected location on this date. Try a different date or location."
                        )
                        .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(bestEvents.enumerated()), id: \.element.id) { index, event in
                                BestTimeCard(
                                    event: event,
                                    objectName: calculation.celestialObject.name,
                                    rank: index + 1
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Card Views

struct SummaryCard: View {
    let calculation: AlignmentCalculation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: calculation.celestialObject.type.icon)
                    .foregroundColor(colorForCelestialType(calculation.celestialObject.type))
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(calculation.celestialObject.name)
                        .font(.headline)
                    Text("Alignment Analysis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(calculation.landmark.name ?? "Selected Location")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(calculation.targetDate, style: .date)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    private func colorForCelestialType(_ type: CelestialType) -> Color {
        switch type {
        case .sun: return .yellow
        }
    }
}

struct TimelineEventCard: View {
    let event: AlignmentEvent
    let objectName: String
    
    var qualityColor: Color {
        if event.alignmentQuality > 0.8 { return .green }
        if event.alignmentQuality > 0.6 { return Color.accentColor }
        if event.alignmentQuality > 0.3 { return .yellow }
        return .red
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.timestamp, style: .time)
                    .font(.headline)
                
                Text(String(format: "%.1f° elevation", event.elevation))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Circle()
                        .fill(qualityColor)
                        .frame(width: 8, height: 8)
                    Text(qualityDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(String(format: "%.0f° azimuth", event.azimuth))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var qualityDescription: String {
        if event.elevation < 0 { return "Below horizon" }
        if event.alignmentQuality > 0.8 { return "Excellent" }
        if event.alignmentQuality > 0.6 { return "Good" }
        if event.alignmentQuality > 0.3 { return "Fair" }
        return "Poor"
    }
}

struct BestTimeCard: View {
    let event: AlignmentEvent
    let objectName: String
    let rank: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(rank)")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .frame(width: 30, alignment: .leading)
                
                VStack(alignment: .leading) {
                    Text(event.timestamp, style: .time)
                        .font(.headline)
                    Text(event.timestamp, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(String(format: "%.0f%%", event.alignmentQuality * 100))
                        .font(.headline)
                        .foregroundColor(.green)
                    Text("Quality")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Label(String(format: "%.1f°", event.elevation), systemImage: "arrow.up")
                Label(String(format: "%.0f°", event.azimuth), systemImage: "safari")
                Spacer()
                Label(UnitFormatter.formatDistance(event.distance, useMetric: UnitFormatter.isMetric()), systemImage: "ruler")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Map Control Menu

struct MapControlMenu: View {
    @Binding var mapType: MKMapType
    let onLocationTap: () -> Void
    @State private var isExpanded = false
    
    var currentMapIcon: String {
        switch mapType {
        case .standard:
            return "map"
        case .satellite:
            return "globe.americas.fill"
        case .hybrid:
            return "map.fill"
        default:
            return "map"
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            if isExpanded {
                // Map Type Options (shown when expanded)
                VStack(spacing: 4) {
                    // Standard Map
                    if mapType != .standard {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                mapType = .standard
                            }
                        }) {
                            Image(systemName: "map")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Satellite Map
                    if mapType != .satellite {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                mapType = .satellite
                            }
                        }) {
                            Image(systemName: "globe.americas.fill")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Hybrid Map
                    if mapType != .hybrid {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                mapType = .hybrid
                            }
                        }) {
                            Image(systemName: "map.fill")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            // Separator line when expanded
            if isExpanded {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                    .frame(width: 30)
                    .padding(.vertical, 4)
            }
            
            // Current Map Type Button (toggle expand)
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: currentMapIcon)
                    .font(.body)
                    .foregroundColor(isExpanded ? .accentColor : .primary)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            
            // User Location Button (at bottom)
            Button(action: onLocationTap) {
                Image(systemName: "location.circle.fill")
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Horizon Results View

/// Mock data structure for horizon calculations
struct HorizonEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let time: Date
    let azimuth: Double
    let terrainElevation: Double
    let distance: Double
    
    enum EventType {
        case rise
        case set
        case transit  // For objects that may cross horizon multiple times
        
        var icon: String {
            switch self {
            case .rise: return "sunrise.fill"
            case .set: return "sunset.fill"
            case .transit: return "arrow.up.circle.fill"
            }
        }
        
        var label: String {
            switch self {
            case .rise: return "Rise"
            case .set: return "Set"
            case .transit: return "Visible"
            }
        }
        
        var color: Color {
            switch self {
            case .rise: return .orange
            case .set: return .purple
            case .transit: return .blue
            }
        }
    }
}

struct HorizonResultsSheet: View {
    let observerLocation: String
    let date: Date
    let celestialObject: CelestialObject
    let events: [HorizonEvent]
    let onViewResults: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 50 {
                                onDismiss()
                            }
                            dragOffset = 0
                        }
                )
            
            ScrollView {
                VStack(spacing: 20) {
                    // Success Icon
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Horizon Analysis Complete")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(observerLocation)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Date and Celestial Object
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(formatDate(date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: celestialObject.type.icon)
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(celestialObject.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    
                    // Summary Stats
                    HStack(spacing: 20) {
                        StatCard(
                            icon: "chart.line.uptrend.xyaxis",
                            value: "\(events.count)",
                            label: "Events"
                        )
                        
                        if let firstRise = events.first(where: { $0.type == .rise }) {
                            StatCard(
                                icon: "clock",
                                value: formatTime(firstRise.time),
                                label: "First Rise"
                            )
                        }
                    }
                    
                    // Events List
                    if !events.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Horizon Events")
                                .font(.headline)
                                .padding(.horizontal, 4)
                            
                            ForEach(events) { event in
                                HorizonEventCard(event: event)
                            }
                        }
                        .padding(.top, 8)
                    } else {
                        EmptyStateCard(
                            icon: "moon.stars",
                            title: "No Events Today",
                            description: "The \(celestialObject.name.lowercased()) does not rise or set at this location on this date."
                        )
                    }
                    
                    // Action Buttons
                    if !events.isEmpty {
                        VStack(spacing: 12) {
                            Button(action: onViewResults) {
                                HStack {
                                    Image(systemName: "map")
                                    Text("View on Map")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            HStack(spacing: 12) {
                                Button(action: onSave) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("Save")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                
                                Button(action: onDismiss) {
                                    HStack {
                                        Image(systemName: "xmark")
                                        Text("Dismiss")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
        .offset(y: dragOffset)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct HorizonEventCard: View {
    let event: HorizonEvent
    
    var body: some View {
        HStack(spacing: 16) {
            // Event Type Icon
            ZStack {
                Circle()
                    .fill(event.type.color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: event.type.icon)
                    .font(.title3)
                    .foregroundColor(event.type.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.type.label)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(formatTime(event.time))
                        .font(.headline)
                        .foregroundColor(event.type.color)
                }
                
                HStack(spacing: 12) {
                    Label(String(format: "%.0f°", event.azimuth), systemImage: "safari")
                    Label(String(format: "%.0f°", event.terrainElevation), systemImage: "mountain.2")
                    Label(UnitFormatter.formatDistance(event.distance, useMetric: UnitFormatter.isMetric()), systemImage: "ruler")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    MapSelectionView(calculationStore: CalculationStore(), selectedTab: .constant(0))
}

// MARK: - Horizon Results Preview

#Preview("Horizon Results") {
    let sampleEvents = [
        HorizonEvent(type: .rise, time: Date().addingTimeInterval(-3600 * 3), azimuth: 94.5, terrainElevation: 12.3, distance: 8420),
        HorizonEvent(type: .set, time: Date().addingTimeInterval(3600 * 5), azimuth: 246.8, terrainElevation: 8.7, distance: 12340)
    ]
    
    return HorizonResultsSheet(
        observerLocation: "Francis Peak",
        date: Date(),
        celestialObject: .sun,
        events: sampleEvents,
        onViewResults: {},
        onSave: {},
        onDismiss: {}
    )
}
