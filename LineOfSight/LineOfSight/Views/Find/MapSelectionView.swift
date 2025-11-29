//
//  MapSelectionView.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import SwiftUI
import MapKit
import UIKit

struct MapSelectionView: View {
    let calculationStore: CalculationStore
    @Binding var selectedTab: Int
    @StateObject private var viewModel: FindViewModel
    @State private var showingCelestialObjectPicker = false
    @State private var showingDatePicker = false
    @State private var isSearching = false
    @State private var hasResults = false
    
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
                onLocationSelected: { coordinate in
                    viewModel.selectLocation(at: coordinate)
                }
            )
            .ignoresSafeArea()
            
            // Overlay Controls
            VStack {
                // Search Bar or Compact Top Control Bar
                if isSearching {
                    LocationSearchBar(
                        isSearching: $isSearching,
                        regionBias: viewModel.mapRegion
                    ) { mapItem in
                        handleSearchSelection(mapItem)
                    }
                    .padding(.horizontal)
                    .padding(.top)
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
                        
                        Spacer()
                        
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
                                .background(.orange, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        // User Location Button
                        Button(action: viewModel.centerOnUserLocation) {
                            Image(systemName: "location.circle.fill")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Bottom Action Area
                HStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        // Calculate Button (when location selected but no results)
                        if viewModel.selectedLocation != nil && !hasResults {
                            Button(action: {
                                Task {
                                    await viewModel.calculateMinuteIntersections()
                                    hasResults = true
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "scope")
                                    Text("Calculate")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.orange, in: Capsule())
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
                                    if !viewModel.minuteIntersections.isEmpty {
                                        Text("(\(viewModel.minuteIntersections.count))")
                                            .font(.caption)
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.blue, in: Capsule())
                            }
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                    }
                    .padding(.trailing)
                    .padding(.bottom, 20)
                }
            }
            
            // Calculation Progress Sheet
            if viewModel.showCalculationSheet, let state = viewModel.calculationState {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
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
    let onLocationSelected: (CLLocationCoordinate2D) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        
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
                
                return annotationView
            }
            
            // Location annotation (POI)
            if annotation is LocationAnnotation {
                let identifier = "LocationPin"
                let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                
                annotationView.annotation = annotation
                annotationView.markerTintColor = .red
                annotationView.glyphImage = UIImage(systemName: "mappin")
                annotationView.canShowCallout = true
                annotationView.displayPriority = .required
                
                return annotationView
            }
            
            return nil
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
        return String(format: "Sun: %.1f° Az, %.1f° El • %.1f km",
                     intersection.sunAzimuth,
                     intersection.sunElevation,
                     intersection.distance / 1000)
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
                    Label(String(format: "%.0fm elevation (DEM)", location.elevation), systemImage: "mountain.2")
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
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 4) {
                    Image(systemName: location.source.icon)
                    Text(location.precision.displayName)
                    
                    if viewModel.isLoading {
                        Text("• Fetching elevation...")
                            .foregroundColor(.orange)
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
                .foregroundColor(.orange)
            
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
                            .foregroundColor(.orange)
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
        if event.alignmentQuality > 0.6 { return .orange }
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
                    .foregroundColor(.orange)
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
                Label(String(format: "%.1fkm", event.distance / 1000), systemImage: "ruler")
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

#Preview {
    MapSelectionView(calculationStore: CalculationStore(), selectedTab: .constant(0))
}