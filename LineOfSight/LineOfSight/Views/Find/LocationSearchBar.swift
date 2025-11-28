//
//  LocationSearchBar.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/28/25.
//

import SwiftUI
import MapKit

/// Search bar with Maps-style location autocomplete
struct LocationSearchBar: View {
    @Binding var isSearching: Bool
    @StateObject private var searchCompleter = LocationSearchCompleter()
    let regionBias: MKCoordinateRegion?
    let onLocationSelected: (MKMapItem) -> Void
    
    init(isSearching: Binding<Bool>, regionBias: MKCoordinateRegion? = nil, onLocationSelected: @escaping (MKMapItem) -> Void) {
        self._isSearching = isSearching
        self.regionBias = regionBias
        self.onLocationSelected = onLocationSelected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search for a location", text: $searchCompleter.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                
                if !searchCompleter.searchText.isEmpty {
                    Button(action: {
                        searchCompleter.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isSearching = false
                        searchCompleter.searchText = ""
                    }
                }) {
                    Text("Cancel")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            
            // Search Results
            if !searchCompleter.directSearchResults.isEmpty || !searchCompleter.results.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Direct search results (geographic features) - shown first
                        if !searchCompleter.directSearchResults.isEmpty {
                            Section {
                                ForEach(searchCompleter.directSearchResults, id: \.self) { mapItem in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3)) {
                                            isSearching = false
                                            searchCompleter.searchText = ""
                                            onLocationSelected(mapItem)
                                        }
                                    }) {
                                        HStack(spacing: 12) {
                                            // Mountain emoji for geographic features
                                            Text("⛰️")
                                                .font(.title3)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(mapItem.name ?? "Unknown")
                                                    .foregroundColor(.primary)
                                                    .font(.body)
                                                
                                                if let placemark = mapItem.placemark.subLocality ?? mapItem.placemark.locality {
                                                    Text(placemark + (mapItem.placemark.administrativeArea != nil ? ", \(mapItem.placemark.administrativeArea!)" : ""))
                                                        .foregroundColor(.secondary)
                                                        .font(.caption)
                                                } else if let state = mapItem.placemark.administrativeArea {
                                                    Text(state)
                                                        .foregroundColor(.secondary)
                                                        .font(.caption)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            } header: {
                                if !searchCompleter.results.isEmpty {
                                    Text("GEOGRAPHIC FEATURES")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                        
                        // Completer results (addresses and POIs)
                        ForEach(searchCompleter.results, id: \.self) { result in
                            Button(action: {
                                searchCompleter.selectResult(result) { mapItem in
                                    withAnimation(.spring(response: 0.3)) {
                                        isSearching = false
                                        searchCompleter.searchText = ""
                                        onLocationSelected(mapItem)
                                    }
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .foregroundColor(.primary)
                                        .font(.body)
                                    
                                    Text(result.subtitle)
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial)
                .frame(maxHeight: 400)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .task {
            if let region = regionBias {
                searchCompleter.regionBias = region
            }
        }
    }
}

/// ViewModel for location search with MKLocalSearchCompleter
@MainActor
class LocationSearchCompleter: NSObject, ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var directSearchResults: [MKMapItem] = []
    
    private let completer: MKLocalSearchCompleter
    var regionBias: MKCoordinateRegion?
    private var directSearchTask: Task<Void, Never>?
    
    override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        
        completer.delegate = self
        // Include all result types to find geographic features, addresses, and POIs
        completer.resultTypes = [.address, .pointOfInterest, .query]
        
        // Observe search text changes
        Task { @MainActor in
            for await value in $searchText.values {
                if value.isEmpty {
                    results = []
                    directSearchResults = []
                    completer.cancel()
                    directSearchTask?.cancel()
                } else {
                    // Update region if available to bias results to visible area
                    if let region = regionBias {
                        completer.region = MKCoordinateRegion(
                            center: region.center,
                            span: MKCoordinateSpan(
                                latitudeDelta: region.span.latitudeDelta * 2,
                                longitudeDelta: region.span.longitudeDelta * 2
                            )
                        )
                    }
                    completer.queryFragment = value
                    
                    // Also perform a direct search for natural features
                    performDirectSearch(query: value)
                }
            }
        }
    }
    
    /// Perform a direct MKLocalSearch to find natural features and geographic locations
    private func performDirectSearch(query: String) {
        // Cancel any existing search
        directSearchTask?.cancel()
        
        directSearchTask = Task { @MainActor in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            
            // Set region if available
            if let region = regionBias {
                request.region = MKCoordinateRegion(
                    center: region.center,
                    span: MKCoordinateSpan(
                        latitudeDelta: region.span.latitudeDelta * 3,
                        longitudeDelta: region.span.longitudeDelta * 3
                    )
                )
            }
            
            // Search for natural features, landmarks, and physical features
            if #available(iOS 18.0, *) {
                request.resultTypes = [.pointOfInterest, .physicalFeature]
            } else {
                request.resultTypes = [.pointOfInterest]
            }
            
            let search = MKLocalSearch(request: request)
            
            do {
                let response = try await search.start()
                
                // Filter for actual geographic features (mountains, peaks, etc.)
                let geoFeatures = response.mapItems.filter { item in
                    // Look for keywords that indicate natural features
                    let name = item.name?.lowercased() ?? ""
                    let category = item.pointOfInterestCategory?.rawValue.lowercased() ?? ""
                    
                    return name.contains("peak") || 
                           name.contains("mountain") || 
                           name.contains("summit") ||
                           name.contains("ridge") ||
                           name.contains("butte") ||
                           name.contains("mesa") ||
                           name.contains("volcano") ||
                           category.contains("mountain") ||
                           category.contains("naturalfeature")
                }
                
                if !Task.isCancelled {
                    self.directSearchResults = geoFeatures
                }
            } catch {
                if !Task.isCancelled {
                    print("Direct search error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Convert a search completion to a map item
    func selectResult(_ result: MKLocalSearchCompletion, completion: @escaping (MKMapItem) -> Void) {
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { response, error in
            guard let response = response,
                  let mapItem = response.mapItems.first else {
                return
            }
            
            DispatchQueue.main.async {
                completion(mapItem)
            }
        }
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationSearchCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.results = completer.results
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
    }
}
