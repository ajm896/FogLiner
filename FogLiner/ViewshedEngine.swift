//
//  ViewshedEngine.swift
//  FogLiner
//
//  Created by Albert Morris on 6/29/26.
//

// No MapKit / UIKit / AppKit / CoreLocation imports — this file must stay pure Swift.

/// Parameters governing a viewshed computation.
struct ViewshedParameters {
    /// Observer eye height above ground, in metres (default 1.7 m).
    var eyeHeight: Double = 1.7
    /// Maximum visibility range, in metres.
    var maxRange: Double
    /// Earth radius in metres (mean spherical).
    var earthRadius: Double = 6_371_000
    /// Atmospheric refraction coefficient (k ≈ 0.13 → effective radius 7R/6).
    var refractionK: Double = 0.13
}

/// A closure that returns terrain elevation (metres) for a planar ENU point.
/// - Parameters:
///   - eastMeters: east offset from the grid origin, in metres
///   - northMeters: north offset from the grid origin, in metres
/// - Returns: elevation in metres, or `nil` if the point falls outside sampled data.
typealias ElevationSampler = (_ eastMeters: Double, _ northMeters: Double) ->
    Double?

/// Pure-Swift viewshed engine. No Apple-framework imports.
///
/// All coordinates inside the kernel are planar ENU metres.
/// Geographic ↔ ENU conversion is the caller's responsibility.
struct ViewshedEngine {
    let parameters: ViewshedParameters

    init(parameters: ViewshedParameters) {
        self.parameters = parameters
    }

    /// Compute a full-area viewshed on a regular grid.
    ///
    /// - Parameters:
    ///   - observer: ENU position of the observer (east, north, elevation in metres).
    ///   - grid: describes the output grid — origin, cell size, and dimensions.
    ///   - sample: elevation sampler for arbitrary ENU positions.
    /// - Returns: a `VisibilityMask` with one cell per grid point.
    func areaViewshed(
        observer: ENUPoint,
        grid: ViewshedGrid,
        sample: ElevationSampler
    ) -> VisibilityMask {
        fatalError("not implemented")
    }

    /// Test whether a single target point is visible from the observer.
    ///
    /// Marches in steps ≤ 0.5 grid cells, tracks the running-max elevation angle,
    /// and applies earth-curvature + refraction correction at each step.
    ///
    /// - Parameters:
    ///   - observer: ENU position of the observer.
    ///   - target: ENU position of the target.
    ///   - stepMeters: march step size (must be ≤ 0.5 × grid cell size).
    ///   - sample: elevation sampler.
    /// - Returns: `.visible`, `.occluded`, or `.outOfRange`.
    func isVisible(
        observer: ENUPoint,
        target: ENUPoint,
        stepMeters: Double,
        sample: ElevationSampler
    ) -> CellState {
        fatalError("not implemented")
    }
}

/// A point in local ENU (East-North-Up) coordinates, all in metres.
struct ENUPoint {
    var east: Double
    var north: Double
    var elevation: Double

    init(east: Double = 0, north: Double = 0, elevation: Double = 0) {
        self.east = east
        self.north = north
        self.elevation = elevation
    }
}

/// Describes the regular grid over which `areaViewshed` computes visibility.
/// Origin is the south-west corner; row 0 is the southernmost row.
struct ViewshedGrid {
    /// ENU position of the cell at (row: 0, col: 0).
    var origin: ENUPoint
    /// Cell size in metres (square cells).
    var cellMeters: Double
    var cols: Int
    var rows: Int
}
