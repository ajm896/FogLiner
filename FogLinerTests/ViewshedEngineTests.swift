//
//  ViewshedEngineTests.swift
//  FogLiner
//
//  Created by Albert Morris on 6/29/26.
//

import Testing
@testable import FogLiner

// MARK: - Synthetic terrain helpers

private func flatSampler(elevation: Double) -> ElevationSampler {
    { _, _ in elevation }
}

/// Linear ramp: elevation = baseElevation + slope * eastMeters
private func eastRampSampler(base: Double, slope: Double) -> ElevationSampler {
    { east, _ in base + slope * east }
}

/// Cone: peak at (peakEast, peakNorth) with given height, falling off linearly to 0 at radius.
private func coneSampler(peakEast: Double, peakNorth: Double,
                          peakHeight: Double, radius: Double) -> ElevationSampler {
    { east, north in
        let d = ((east - peakEast) * (east - peakEast) + (north - peakNorth) * (north - peakNorth)).squareRoot()
        return max(0, peakHeight * (1 - d / radius))
    }
}

private let defaultParams = ViewshedParameters(maxRange: 10_000)
private let stepMeters = 5.0

// MARK: - isVisible tests

@Suite struct IsVisibleTests {

    // Flat terrain: every point within range must be visible from the observer.
    @Test func flatTerrain_allVisible() {
        let engine = ViewshedEngine(parameters: defaultParams)
        let observer = ENUPoint(east: 0, north: 0, elevation: 1.7)
        let sampler = flatSampler(elevation: 0)

        for dist in stride(from: 100.0, through: 5000.0, by: 500.0) {
            let target = ENUPoint(east: dist, north: 0, elevation: 0)
            #expect(engine.isVisible(observer: observer, target: target,
                                     stepMeters: stepMeters, sample: sampler) == .visible)
        }
    }

    // A target beyond maxRange must return .outOfRange regardless of terrain.
    @Test func beyondMaxRange_isOutOfRange() {
        let params = ViewshedParameters(maxRange: 1000)
        let engine = ViewshedEngine(parameters: params)
        let observer = ENUPoint(east: 0, north: 0, elevation: 1.7)
        let target = ENUPoint(east: 1001, north: 0, elevation: 0)
        let sampler = flatSampler(elevation: 0)

        #expect(engine.isVisible(observer: observer, target: target,
                                 stepMeters: stepMeters, sample: sampler) == .outOfRange)
    }

    // A wall (tall spike) between observer and target must occlude the target.
    @Test func wallBetweenObserverAndTarget_isOccluded() {
        let engine = ViewshedEngine(parameters: defaultParams)
        let observer = ENUPoint(east: 0, north: 0, elevation: 1.7)
        let target = ENUPoint(east: 1000, north: 0, elevation: 0)

        // A 200 m wall at east=500 m fully blocks the sightline.
        let sampler: ElevationSampler = { east, _ in
            (east > 490 && east < 510) ? 200.0 : 0.0
        }
        #expect(engine.isVisible(observer: observer, target: target,
                                 stepMeters: stepMeters, sample: sampler) == .occluded)
    }

    // Observer on top of a cone sees the surroundings; behind the cone is occluded.
    @Test func cone_topIsVisible_behindIsOccluded() {
        let engine = ViewshedEngine(parameters: defaultParams)
        // Peak at origin, 300 m high, radius 500 m.
        let sampler = coneSampler(peakEast: 0, peakNorth: 0, peakHeight: 300, radius: 500)
        let groundAtOrigin = sampler(0, 0)!  // 300 m
        let observer = ENUPoint(east: 0, north: 0, elevation: groundAtOrigin + 1.7)

        // A point just at the edge of the cone (flat ground) should be visible.
        let nearEdge = ENUPoint(east: 490, north: 0, elevation: sampler(490, 0)!)
        #expect(engine.isVisible(observer: observer, target: nearEdge,
                                 stepMeters: stepMeters, sample: sampler) == .visible)

        // A point behind the cone (beyond radius, at ground level 0) should be occluded.
        let behind = ENUPoint(east: 800, north: 0, elevation: 0)
        #expect(engine.isVisible(observer: observer, target: behind,
                                 stepMeters: stepMeters, sample: sampler) == .occluded)
    }

    // Upward ramp: observer at low end, target at high end → visible (target is "uphill").
    @Test func upwardRamp_targetVisible() {
        let engine = ViewshedEngine(parameters: defaultParams)
        // Ramp: slope = 0.1 (rises 10 m per 100 m east).
        let sampler = eastRampSampler(base: 0, slope: 0.1)
        let observer = ENUPoint(east: 0, north: 0, elevation: 1.7)
        let target = ENUPoint(east: 500, north: 0, elevation: sampler(500, 0)!)
        #expect(engine.isVisible(observer: observer, target: target,
                                 stepMeters: stepMeters, sample: sampler) == .visible)
    }

    // Downward ramp: observer at high end, target at low end → visible (no occlusion in front).
    @Test func downwardRamp_targetVisible() {
        let engine = ViewshedEngine(parameters: defaultParams)
        let sampler = eastRampSampler(base: 100, slope: -0.1)
        let groundAtOrigin = sampler(0, 0)!
        let observer = ENUPoint(east: 0, north: 0, elevation: groundAtOrigin + 1.7)
        let target = ENUPoint(east: 500, north: 0, elevation: sampler(500, 0)!)
        #expect(engine.isVisible(observer: observer, target: target,
                                 stepMeters: stepMeters, sample: sampler) == .visible)
    }
}

// MARK: - areaViewshed tests

@Suite struct AreaViewshedTests {

    // On perfectly flat terrain every cell within range must be .visible.
    @Test func flatTerrain_allCellsVisible() {
        let engine = ViewshedEngine(parameters: ViewshedParameters(maxRange: 1000))
        let sampler = flatSampler(elevation: 0)
        let grid = ViewshedGrid(origin: ENUPoint(east: -500, north: -500),
                                cellMeters: 50, cols: 21, rows: 21)
        let observer = ENUPoint(east: 0, north: 0, elevation: 1.7)

        let mask = engine.areaViewshed(observer: observer, grid: grid, sample: sampler)

        #expect(mask.cols == 21)
        #expect(mask.rows == 21)

        for row in 0..<mask.rows {
            for col in 0..<mask.cols {
                let state = mask[row, col]
                // outOfRange cells at corners are fine; no cell should be .occluded on flat ground.
                #expect(state != .occluded,
                        "Expected not-occluded at (\(row),\(col)), got \(state)")
            }
        }
    }

    // Cells beyond maxRange must all be .outOfRange.
    @Test func cellsBeyondRange_areOutOfRange() {
        let params = ViewshedParameters(maxRange: 200)
        let engine = ViewshedEngine(parameters: params)
        let sampler = flatSampler(elevation: 0)
        // Grid spans −500…500 m; maxRange is 200 m.
        let grid = ViewshedGrid(origin: ENUPoint(east: -500, north: -500),
                                cellMeters: 100, cols: 11, rows: 11)
        let observer = ENUPoint(east: 0, north: 0, elevation: 1.7)

        let mask = engine.areaViewshed(observer: observer, grid: grid, sample: sampler)

        // Corners are > 700 m away → must be outOfRange.
        #expect(mask[0, 0] == .outOfRange)
        #expect(mask[0, 10] == .outOfRange)
        #expect(mask[10, 0] == .outOfRange)
        #expect(mask[10, 10] == .outOfRange)
    }

    // A cone behind the observer should produce some .occluded cells on the far side.
    @Test func cone_producesOccludedCells() {
        let params = ViewshedParameters(maxRange: 5000)
        let engine = ViewshedEngine(parameters: params)
        // Cone: peak 500 m east of observer, 300 m high, radius 400 m.
        let sampler = coneSampler(peakEast: 500, peakNorth: 0, peakHeight: 300, radius: 400)
        let grid = ViewshedGrid(origin: ENUPoint(east: -100, north: -500),
                                cellMeters: 100, cols: 30, rows: 11)
        let observer = ENUPoint(east: 0, north: 0, elevation: 1.7)

        let mask = engine.areaViewshed(observer: observer, grid: grid, sample: sampler)

        // At least one cell far east of the cone must be occluded.
        let farEastOccluded = (0..<mask.rows).contains { row in
            (0..<mask.cols).contains { col in
                let cellEast = grid.origin.east + Double(col) * grid.cellMeters
                return cellEast > 1000 && mask[row, col] == .occluded
            }
        }
        #expect(farEastOccluded)
    }

    // VisibilityMask dimensions must match the requested grid.
    @Test func maskDimensionsMatchGrid() {
        let engine = ViewshedEngine(parameters: ViewshedParameters(maxRange: 1000))
        let sampler = flatSampler(elevation: 0)
        let grid = ViewshedGrid(origin: ENUPoint(), cellMeters: 10, cols: 7, rows: 13)
        let mask = engine.areaViewshed(observer: ENUPoint(elevation: 1.7), grid: grid, sample: sampler)
        #expect(mask.cols == 7)
        #expect(mask.rows == 13)
    }
}

// MARK: - VisibilityMask unit tests

@Suite struct VisibilityMaskTests {
    @Test func defaultStateIsOutOfRange() {
        let mask = VisibilityMask(cols: 3, rows: 3)
        for r in 0..<3 { for c in 0..<3 {
            #expect(mask[r, c] == .outOfRange)
        }}
    }

    @Test func subscriptRoundTrips() {
        var mask = VisibilityMask(cols: 4, rows: 4, initialState: .outOfRange)
        mask[1, 2] = .visible
        mask[3, 0] = .occluded
        #expect(mask[1, 2] == .visible)
        #expect(mask[3, 0] == .occluded)
        #expect(mask[0, 0] == .outOfRange)
    }
}
