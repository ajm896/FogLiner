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
    // THE M1 gate. Blocked on tile-cover math (lat/lon -> z/x/y) + bilinear geo-sampling.
    @Test(.disabled("Needs tile-cover math + bilinear geo-sampling"))
    func summitElevationWithinTolerance() {
        // let h = try await dem.elevation(atLat: Fixtures.coldMountainLat,
        //                                 lon: Fixtures.coldMountainLon)
        // #expect(abs(h - Fixtures.coldMountainMeters) <= Fixtures.toleranceMeters)
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
