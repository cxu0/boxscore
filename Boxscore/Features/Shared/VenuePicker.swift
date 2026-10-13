import SwiftUI
import MapKit
import Combine

/// Gym field: shows the picked venue, or a search box backed by Apple Maps
/// autocomplete. Picking a result resolves its coordinates and city.
struct VenuePickerField: View {
    @Binding var venue: Venue?

    @StateObject private var search = VenueSearch()
    @State private var query = ""
    @State private var isResolving = false

    var body: some View {
        if let venue {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Brand.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name).font(.system(size: 15, weight: .bold))
                    if let line = venue.address ?? venue.city {
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Change") {
                    self.venue = nil
                    query = ""
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.orange)
            }
            .brandCard(padding: 14)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                BrandTextField(placeholder: "Search for your gym", text: $query)
                    .autocorrectionDisabled()
                    .onChange(of: query) { _, newValue in search.update(query: newValue) }

                if isResolving {
                    ProgressView().frame(maxWidth: .infinity).padding(8)
                } else if !query.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(search.results.prefix(5).enumerated()), id: \.offset) { index, result in
                            if index > 0 { Divider() }
                            Button {
                                Task { await pick(result) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first else {
            return
        }
        venue = Venue(
            name: item.name ?? completion.title,
            address: item.address?.shortAddress ?? item.address?.fullAddress,
            city: item.addressRepresentations?.cityName,
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude
        )
    }
}

/// Wraps MKLocalSearchCompleter for SwiftUI.
@MainActor
final class VenueSearch: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.pointOfInterest, .address]
        completer.delegate = self
        // Favor gyms near the organizer when we already have permission
        // (never prompts — the last known fix is enough).
        if let here = CLLocationManager().location {
            completer.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
        }
    }

    func update(query: String) {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            results = []
        } else {
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

/// One-shot "where am I?" for the Near you list. Asks for permission the
/// first time `request()` is called.
@MainActor
final class LocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var status: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool { status == .denied || status == .restricted }
    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    func request() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if isAuthorized { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Opens the venue in Apple Maps.
func openInMaps(_ venue: Venue) {
    let item = MKMapItem(
        location: CLLocation(latitude: venue.latitude, longitude: venue.longitude),
        address: nil
    )
    item.name = venue.name
    item.openInMaps()
}
