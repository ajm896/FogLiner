import MapKit
import Playgrounds
import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Default fetch zoom for on-demand elevation sampling (~7.8 m/px in western NC).
private let elevationSampleZoom = 14

struct ContentView: View {
    @State private var selectedPoint: SelectedPoint?
    private let elevationSource = TileSource<HeightField>(
        decode: { data, key in try HeightField(key: key, from: data) }
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            SatelliteMapView(selectedPoint: $selectedPoint, onTap: sample)

            Text("Terrain data © Mapzen, Joerd (AWS Terrain Tiles)")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 8)
        }
        .ignoresSafeArea()
    }

    private func sample(coordinate: CLLocationCoordinate2D) {
        selectedPoint = SelectedPoint(coordinate: coordinate)
        let key = TileKey.containing(
            lat: coordinate.latitude, lon: coordinate.longitude, zoom: elevationSampleZoom)

        Task { @MainActor in
            do {
                let tile = try await elevationSource.tile(key)
                let meters = tile.elevation(atLat: coordinate.latitude, lon: coordinate.longitude)
                guard selectedPoint?.coordinate.latitude == coordinate.latitude,
                    selectedPoint?.coordinate.longitude == coordinate.longitude
                else { return }
                selectedPoint?.elevationMeters = meters
            } catch {
                guard selectedPoint?.coordinate.latitude == coordinate.latitude,
                    selectedPoint?.coordinate.longitude == coordinate.longitude
                else { return }
                selectedPoint?.errorMessage = "Couldn't sample elevation"
            }
        }
    }
}

#Preview {
    ContentView()
}
