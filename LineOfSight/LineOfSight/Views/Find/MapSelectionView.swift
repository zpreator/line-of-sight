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
    @StateObject private var viewModel = FindViewModel()
    @State private var showingCelestialObjectPicker = false
    @State private var showingDatePicker = false
    
    var body: some View {
        ZStack {
            // Main Map View
            InteractiveMapView(
                region: $viewModel.mapRegion,
                selectedLocation: viewModel.selectedLocation,
                onLocationSelected: { coordinate in
                    viewModel.selectLocation(at: coordinate)
                }
            )
            .ignoresSafeArea()
            
            // Overlay Controls
            VStack {
                // Top Control Bar
                HStack {
                    // User Location Button
                    Button(action: viewModel.centerOnUserLocation) {
                        Image(systemName: "location.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Circle().fill(.black.opacity(0.7)))
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    // Map Style Toggle (Future Implementation)
                    Button(action: {}) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Circle().fill(.black.opacity(0.7)))
                            .frame(width: 44, height: 44)
                    }
                }
                .padding()
                
                Spacer()
                
                // Bottom Control Panel
                VStack(spacing: 16) {
                    // Celestial Object Selection
                    HStack {
                        Text("Object:")
                            .foregroundColor(.secondary)
                        
                        Button(action: { showingCelestialObjectPicker = true }) {
                            HStack {
                                Image(systemName: viewModel.selectedCelestialObject.type.icon)
                                Text(viewModel.selectedCelestialObject.name)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        
                        Spacer()
                    }
                    
                    // Date Selection
                    HStack {
                        Text("Date:")
                            .foregroundColor(.secondary)
                        
                        Button(action: { showingDatePicker = true }) {
                            HStack {
                                Image(systemName: "calendar")
                                Text(viewModel.targetDate, style: .date)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        
                        Spacer()
                    }
                    
                    // Selected Location Info
                    if let location = viewModel.selectedLocation {
                        LocationInfoCard(location: location, viewModel: viewModel)
                    } else {
                        LocationPromptCard()
                    }
                    
                    // Calculate Button
                    if viewModel.selectedLocation != nil {
                        Button(action: {
                            if let calculation = viewModel.calculateAlignment() {
                                calculationStore.setCurrentCalculation(calculation)
                                selectedTab = 1 // Navigate to Results tab
                            }
                        }) {
                            HStack {
                                Image(systemName: "scope")
                                Text("Calculate Alignment")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
            
            // Loading Overlay
            if viewModel.isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                ProgressView("Getting elevation data...")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
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

        .navigationBarHidden(true)
    }
    
}

// MARK: - Interactive Map View

struct InteractiveMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let selectedLocation: Location?
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
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: InteractiveMapView
        
        init(_ parent: InteractiveMapView) {
            self.parent = parent
        }
        
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
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
            guard annotation is LocationAnnotation else {
                return nil
            }
            
            let identifier = "LocationPin"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            
            annotationView.annotation = annotation
            annotationView.markerTintColor = .red
            annotationView.glyphImage = UIImage(systemName: "mappin")
            annotationView.canShowCallout = true
            
            return annotationView
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
            
            HStack {
                Label(String(format: "%.0fm elevation", location.elevation), systemImage: "mountain.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let distance = viewModel.distanceToSelectedLocation() {
                    Label(distance, systemImage: "ruler")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
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
                    in: Date()...,
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