//
//  TileKeyTests.swift
//  FogLiner
//
//  Created by Albert Morris on 6/26/26.
//


import Testing
import Foundation
@testable import FogLiner

extension Tag { @Tag static var network: Self }

@Suite struct TileKeyTests {
    @Test func pathIsZXY() {
        #expect(TileKey(14,4421,6467).toPath() == "14/4421/6467")
    }
    @Test func urlAppendsPathAndExtension() {
        let url = TileKey(1,2,3).toURL(with: "https://example.com/t/")
        #expect(url.absoluteString == "https://example.com/t/1/2/3.png")
    }

    // Cross-checked against a from-scratch Python computation of the standard
    // slippy-map formula; also matches the z14 x-index already used above.
    @Test func containingMatchesColdMountainZ14Tile() {
        let key = TileKey.containing(
            lat: Fixtures.coldMountainLat, lon: Fixtures.coldMountainLon, zoom: 14)
        #expect(key.z == 14)
        #expect(key.x == 4421)
        #expect(key.y == 6466)
    }

    @Test func containingClampsAtWorldEdges() {
        let nw = TileKey.containing(lat: 89.9, lon: -180, zoom: 5)
        #expect(nw.x == 0)
        #expect(nw.y == 0)
        let se = TileKey.containing(lat: -85, lon: 179.9, zoom: 5)
        #expect(se.x == (1 << 5) - 1)
        #expect(se.y == (1 << 5) - 1)
    }

    @Test func fractionalPixelIsWithinTileBounds() {
        let key = TileKey.containing(
            lat: Fixtures.coldMountainLat, lon: Fixtures.coldMountainLon, zoom: 14)
        let (px, py) = key.fractionalPixel(
            lat: Fixtures.coldMountainLat, lon: Fixtures.coldMountainLon)
        #expect(px >= 0 && px < 256)
        #expect(py >= 0 && py < 256)
    }
}

@Suite struct DecodeTests {
    // Covers the formula AND the CGImage byte path, fully offline. -32768 is the void marker.
    @Test(arguments: [0.0, 1838.0, 1838.5, -100.0, -32768.0, 8848.0])
    func decodesKnownElevation(_ meters: Double) throws {
        let png = Fixtures.terrariumPNG(elevations: [meters], width: 1, height: 1)
        let tile = try HeightField(key: TileKey(0, 0,0), from: png)
        #expect(abs(tile.elevation(col: 0, row: 0) - meters) < 0.01)
    }

    @Test func preservesDimensionsAndPerCellValues() throws {
        let w = 4, h = 3
        let elev = (0..<(w*h)).map { Double($0) * 10.0 }
        let png = Fixtures.terrariumPNG(elevations: elev, width: w, height: h)
        let tile = try HeightField(key: TileKey(0,0, 0), from: png)
        #expect(tile.width == w)
        #expect(tile.height == h)
        for row in 0..<h { for col in 0..<w {
            #expect(abs(tile.elevation(col: col, row: row) - elev[row*w+col]) < 0.01)
        }}
    }

    @Test func rejectsNonImageData() {
        #expect(throws: (any Error).self) {
            _ = try HeightField(key: TileKey(0, 0, 0), from: Data("nope".utf8))
        }
    }
}

@Suite struct BilinearGeoSampleTests {
    // A flat tile should read back the same elevation everywhere, including
    // fractional lat/lon that don't land exactly on a pixel.
    @Test func flatTileIsConstantEverywhere() throws {
        let key = TileKey(14, 4421, 6466)
        let png = Fixtures.terrariumPNG(
            elevations: [Double](repeating: 1000.0, count: 256 * 256), width: 256, height: 256)
        let tile = try HeightField(key: key, from: png)

        let (centerLat, centerLon) = key.centerLatLon()
        #expect(abs(tile.elevation(atLat: centerLat, lon: centerLon) - 1000.0) < 0.01)

        let (edgeLat, edgeLon) = key.latLon(px: 0.1, py: 0.1)
        #expect(abs(tile.elevation(atLat: edgeLat, lon: edgeLon) - 1000.0) < 0.01)
    }

    // A left-to-right ramp interpolated at a fractional pixel should land
    // between its two bracketing columns.
    @Test func interpolatesBetweenNeighboringPixels() throws {
        let key = TileKey(14, 4421, 6466)
        var elev = [Double](repeating: 0, count: 256 * 256)
        for row in 0..<256 { for col in 0..<256 { elev[row * 256 + col] = Double(col) * 10.0 } }
        let png = Fixtures.terrariumPNG(elevations: elev, width: 256, height: 256)
        let tile = try HeightField(key: key, from: png)

        let (lat, lon) = key.latLon(px: 101.0, py: 128)
        let sampled = tile.elevation(atLat: lat, lon: lon)
        #expect(sampled > tile.elevation(col: 100, row: 128))
        #expect(sampled < tile.elevation(col: 101, row: 128))
    }

    // Points right at (or past) a tile edge clamp to the tile's own edge
    // pixels rather than reaching into a neighbor tile — the chosen v1 tradeoff.
    @Test func clampsAtTileEdgeRatherThanExtrapolating() throws {
        let key = TileKey(14, 4421, 6466)
        var elev = [Double](repeating: 0, count: 256 * 256)
        for row in 0..<256 { for col in 0..<256 { elev[row * 256 + col] = Double(col) * 10.0 } }
        let png = Fixtures.terrariumPNG(elevations: elev, width: 256, height: 256)
        let tile = try HeightField(key: key, from: png)

        let (lat, lon) = key.latLon(px: 0, py: 128)
        let sampled = tile.elevation(atLat: lat, lon: lon)
        #expect(abs(sampled - tile.elevation(col: 0, row: 128)) < 0.01)
    }
}

private extension TileKey {
    /// Test-only inverse of `fractionalPixel`, for constructing lat/lon at a
    /// known pixel position within this tile.
    func latLon(px: Double, py: Double, tileSize: Double = 256) -> (lat: Double, lon: Double) {
        let n = Double(1 << z)
        let xNorm = (Double(x) + px / tileSize) / n
        let yNorm = (Double(y) + py / tileSize) / n
        let lon = xNorm * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * yNorm))) * 180 / .pi
        return (lat, lon)
    }

    func centerLatLon() -> (lat: Double, lon: Double) {
        latLon(px: 128, py: 128)
    }
}

@Suite(.serialized) struct CacheTests {
    @Test func secondFetchHitsDiskNotNetwork() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(
            data: Fixtures.terrariumPNG(elevations: [1838.0], width: 1, height: 1), status: 200)
        let dir = Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = TileSource<HeightField>(
            urlTemplate: "https://stub.invalid/terrarium/", session: .stubbed(), cacheDir: dir,
            decode: { data, key in try HeightField(key: key, from: data) })
        let key = TileKey(14, 4421, 6467)
        _ = try await source.tile(key)
        _ = try await source.tile(key)

        #expect(StubURLProtocol.hitCount == 1)   // ← the answer to "does caching work"
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "14/4421/6467.png").path))
    }

    @Test func errorResponseIsNotCached() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(data: Data("<Error/>".utf8), status: 404)
        let dir = Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = TileSource<HeightField>(
            urlTemplate: "https://stub.invalid/terrarium/", session: .stubbed(), cacheDir: dir,
            decode: { data, key in try HeightField(key: key, from: data) })
        await #expect(throws: (any Error).self) {
            _ = try await source.tile(TileKey( 14, 4421, 6467))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "14/4421/6467.png").path))
    }
}

@Suite struct ColdMountainGate {
    // THE M1 gate. Hits the live S3 bucket — enable manually (same convention as
    // liveTileDecodesToPlausibleElevations below).
    @Test(.tags(.network), .disabled("hits the live S3 bucket — enable manually"))
    func summitElevationWithinTolerance() async throws {
        let source = TileSource<HeightField>(
            cacheDir: Fixtures.makeTempDir(),
            decode: { data, key in try HeightField(key: key, from: data) })
        let key = TileKey.containing(
            lat: Fixtures.coldMountainLat, lon: Fixtures.coldMountainLon, zoom: 14)
        let tile = try await source.tile(key)
        let h = tile.elevation(atLat: Fixtures.coldMountainLat, lon: Fixtures.coldMountainLon)
        #expect(abs(h - Fixtures.coldMountainMeters) <= Fixtures.toleranceMeters)
    }

    // Live end-to-end smoke test. Tile coords hand-computed; pin exact band when cover-math lands.
    @Test(.tags(.network), .disabled("hits the live S3 bucket — enable manually"))
    func liveTileDecodesToPlausibleElevations() async throws {
        let source = TileSource<HeightField>(
            cacheDir: Fixtures.makeTempDir(),
            decode: { data, key in try HeightField(key: key, from: data) })
        let tile = try await source.tile(TileKey(14, 4421, 6467))
        var maxH = -Double.greatestFiniteMagnitude
        for row in 0..<tile.height { for col in 0..<tile.width {
            maxH = max(maxH, tile.elevation(col: col, row: row))
        }}
        #expect(maxH > 500 && maxH < 2500)
    }
}
