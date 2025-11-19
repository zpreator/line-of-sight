//
//  MapSelectionView.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import SwiftUI
import MapKit

struct MapSelectionView: View {
    @StateObject private var viewModel = FindViewModel()
    @State private var showingCelestialObjectPicker = false
    @State private var showingDatePicker = false
    @State private var showingCalculationResults = false
    
    var body: some View {
        ZStack {
            // Main Map View
            Map(coordinateRegion: $viewModel.mapRegion, 
                interactionModes: [.pan, .zoom],
                showsUserLocation: true,
                annotationItems: viewModel.selectedLocation != nil ? [viewModel.selectedLocation!] : []) { location in
                MapAnnotation(coordinate: location.coordinate) {
                    LocationPin(location: location)
                }
            }
            .onTapGesture { location in
                // Convert tap location to coordinate
                // This is a simplified approach - in production would need proper coordinate conversion
                let coordinate = viewModel.mapRegion.center
                viewModel.selectLocation(at: coordinate)
            }
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
                            showingCalculationResults = true
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
        .sheet(isPresented: $showingCalculationResults) {
            if let calculation = viewModel.calculateAlignment() {
                CalculationResultsView(calculation: calculation)
            }
        }
        .navigationBarHidden(true)
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
                Label("\(Int(location.elevation))m", systemImage: "mountain.2")
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
        case .moon:
            return .gray
        case .planet:
            return .blue
        case .star:
            return .white
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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Calculation Results")
                        .font(.largeTitle)
                        .bold()
                    
                    // Summary Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: calculation.celestialObject.type.icon)
                            Text(calculation.celestialObject.name)
                            Text("alignment with")
                            Text(calculation.landmark.name ?? "Selected location")
                        }
                        .foregroundColor(.secondary)
                        
                        Text("Calculated for \(calculation.targetDate, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                    // Placeholder for future detailed results
                    Text("Detailed alignment calculations and optimal positions will be displayed here.")
                        .foregroundColor(.secondary)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
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

#Preview {
    MapSelectionView()
}