# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- Internal title: Fogline — operating context for AI agents. Read fully before proposing or writing code. Source of truth for scope and constraints. -->

## What Fogline is

Cross-platform SwiftUI app (iOS 17+ / macOS 14+). The user drops an arbitrary pin on a satellite map; the app fetches terrain elevation around it, computes the **viewshed** (every surface point with an unobstructed line of sight from the pin, within an adjustable visibility range), and paints everything occluded or out of range as fog-of-war. The core engine is a **topographic raycaster over a heightfield** — 2.5D (`z = f(x,y)`, no caves/overhangs), which reduces line-of-sight to walking a 1D terrain profile and comparing elevation angles. That simplification is load-bearing; lean on it.

It is a stylistic **map viewer / desk tool**, not a field app.

## Build & Test

No Makefile or scripts — use xcodebuild or Xcode directly.

```bash
# Build (Debug)
xcodebuild -project FogLiner.xcodeproj -scheme FogLiner -configuration Debug build

# Run all tests (macOS)
xcodebuild -project FogLiner.xcodeproj -scheme FogLiner -destination 'platform=macOS' test

# Run a single test suite
xcodebuild -project FogLiner.xcodeproj -scheme FogLiner -destination 'platform=macOS' \
  -only-testing:FogLinerTests/TileKeyTests test
```

Tests use Apple's **`Testing`** framework (not XCTest). Live network tests are tagged `@Tag.network` and skipped by default — they hit the real AWS bucket.

## Two governing principles (do not violate)

1. **Consume what's official; build only what has no official substitute.** Do not reimplement map rendering, base tiling, great-circle distance, or imagery fetching — those are consumed from Apple/AWS. The genuine build surface is the elevation tile pipeline, elevation sampling, the viewshed, and hillshade. Before writing anything from scratch, check whether an official/standard provider already does it. If one does, consume it. If none does, building it is the point.
2. **Respect the scope fences.** The non-goals below are firm. Do not reintroduce them even when they seem helpful.

When two designs are viable, **name the fork and lay out the trade-off** — the human drives architecture. Don't silently pick.

## Hard non-goals

- **No AR** — no ARKit, RealityKit, SceneKit, or camera.
- **No CoreLocation** — no device GPS, heading, or location permissions. The pin is an arbitrary point; the app never needs the *user's* location.
- **No hand-rolling provided infra** — map rendering, base-map tiling, great-circle distance, imagery fetch are all consumed.
- **No bundled DEM data, no GDAL at runtime.** Elevation arrives over the network and is cached to disk.
- **Stands alone** — not coupled to other projects.
- **visionOS is out of scope.**

## Stack

- SwiftUI multiplatform, iOS 17+ / macOS 14+ (iPadOS falls out for free).
- State via `@Observable`.
- Map base: `MKMapView` (`.satellite`) wrapped in a representable shimmed across `UIViewRepresentable` (iOS) / `NSViewRepresentable` (macOS) behind a shared typealias. SwiftUI's native `Map` can't host a custom georeferenced bitmap overlay the way `MKOverlayRenderer` can.
- Fog: `MKOverlay` + `MKOverlayRenderer`, drawn on top, **additive** — never modifies base pixels.
- Compute: plain Swift + `DispatchQueue.concurrentPerform`. Reach for Accelerate only if profiling demands it.

## Architecture — the hard wall

A hard wall separates the compute engine from anything Apple-specific.

- **`TileSource<Payload>`** — generic fetch + tile-cover math + disk cache, parameterized by a decode closure. Cache key = the immutable `{z}/{x}/{y}` triple (no invalidation logic). Written once; currently instantiated for elevation.
- **`DEMTile` / heightfield** — assembles fetched tiles into a sampleable surface. `elevation(atLat:lon:)` uses **bilinear** interpolation (never nearest-neighbor). Grid↔geographic conversions live here.
- **`ViewshedEngine`** — pure Swift. **No `import MapKit / UIKit / AppKit / CoreLocation`.** Operates on a height-sampling abstraction, not MapKit types, so it's unit-testable with synthetic terrain. Surface: `areaViewshed(...) -> VisibilityMask`, `isVisible(...) -> Bool`.
- **`VisibilityMask`** — 2D grid of `enum CellState { case visible, occluded, outOfRange }`. Keep `occluded` and `outOfRange` distinct in the model; collapse to clear-vs-fog only at render time.
- **`ViewshedOverlay` + renderer** — mask → georeferenced `CGImage` (transparent where visible, semi-opaque fog otherwise) → `MKOverlayRenderer` over `.satellite`.
- **SwiftUI layer** — the representable, the controls, an `@Observable` model holding observer, range, eye height, and current mask.

**Invariant:** if a fix requires importing MapKit/UIKit/AppKit/CoreLocation into the engine, the design is wrong. Surface the trade-off instead of crossing the wall.

**Current state (as of mid-2026):** `TileSource<Payload>`, `HeightField` (Terrarium decode + bilinear sample), and `ContentView` (satellite map display) are implemented. `ViewshedEngine`, `VisibilityMask`, and `ViewshedOverlay` + renderer are not yet built.

## Coordinate frames — keep two, never mix

This is where "everything's 200 m off" bugs live. **One conversion site.** Planar metres only inside the kernel.

- **Web Mercator** (`MKMapPoint`, EPSG:3857) for rendering + overlay alignment — matches both the base map and the terrain tiles, so georeferencing the fog overlay is exact.
- **Local ENU / tangent plane** for the physics. Mercator is NOT equidistant. `metersPerDegLat ≈ 111_320`; `metersPerDegLon ≈ 111_320 · cos(lat)`.
- Great-circle distance: consume `CLLocation.distance` — do not hand-roll Haversine.

Slippy tile math (AWS terrarium order is `{z}/{x}/{y}`): `x_norm = (lon+180)/360`; `y_norm = (1 − asinh(tan φ)/π)/2`; `tile = floor(norm · 2^z)`; pixel-in-tile = frac · 256.

## Ground-truth constants (verified — do not hallucinate these)

- **Elevation source:** AWS Terrain Tiles (Mapzen/Joerd), Terrarium PNG, no API key:
  `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` — live and free.
- **Decode** each pixel to metres: `(R*256 + G + B/256) - 32768`.
- **Default fetch zoom: z14** (~7.8 m/px in western NC; matches ~10 m 3DEP). z14/z15 are oversampled where 3 m coverage is absent — don't expect uniform sharpness.
- **Caching:** tiles immutable → cache forever, no staleness logic. A cached z13 parent is a free coarse fallback for a not-yet-fetched z14 child.
- **Attribution:** display a Joerd/Mapzen credit line (terrain tiles require it). Apple handles map attribution via `MKMapView`.
- **M1 validation gate:** Cold Mountain, Haywood County NC (the Shining Rock / Pisgah peak) — 6,030 ft ≈ **1,838 m**, near 35.410°, −82.856°. Tolerance ±~15 m. Do NOT use 1,920 m (wrong). Beware the *other* Cold Mountain in Transylvania County (~1,408 m).

## Viewshed kernel (math)

March observer→target in steps ≤ **0.5 grid cells** (coarser aliases away thin ridges). At each sample distance `d`, bilinearly sample height `h`, then:

- `drop = d² · (1 − k) / (2R)`   (earth curvature + refraction)
- `apparentΔ = (h − eyeElevation) − drop`
- `angle = atan2(apparentΔ, d)`

Track the running-max angle over samples **nearer** than the target; the target is **visible** iff its own `angle` exceeds it. If `d > maxRange` it's `outOfRange` regardless of geometry.

- `R ≈ 6_371_000` m (mean Earth radius — distinct from the equatorial radius used in tile-resolution math). `k ≈ 0.13` (refraction; effective radius `R/(1−k) ≈ 7R/6`).
- Never omit curvature: over 5–40 km it's tens of metres and silently flips marginal far summits.
- `eyeElevation` = sampled ground at the observer + eye height (default 1.7 m).
- **v1 algorithm:** per-target march, O(cells × samples), redundant but trivially hole-free; parallelize with `concurrentPerform`. Validate against a hand-computed sightline before optimizing. Optional later path: radial sweep → Van Kreveld O(n log n).

## Pitfalls (check these first when stuck)

- Sampling step > 0.5 cell → thin ridges vanish.
- Nearest-neighbor sampling → false ridgeline occlusions. Bilinear always.
- Mixing degrees/metres in the engine → the classic offset bug. One conversion site; planar metres only in the kernel.
- Skipping or sign-flipping the curvature term → silently wrong past ~10 km.
- Wrong tile-axis order → AWS terrain is `{z}/{x}/{y}`; ArcGIS-hosted services are `{z}/{y}/{x}`. We use AWS.
- Recompute on the main thread → janky map. Background queue, swap overlay on completion.

## When stuck (agent guidance)

- Verify any external fact — endpoints, decode formulas, source resolutions — against the live web before acting; training data goes stale. The constants above are verified; treat anything new with suspicion.
- Reproduce with the smallest synthetic terrain (flat / ramp / cone) that exhibits the bug before touching the full pipeline. The engine is pure for exactly this reason.
- Validate elevation against the Cold Mountain gate; validate sightlines against a hand-computed profile.
- Recompute always runs off the main thread; the overlay is swapped on completion.
- Present design forks; let the human choose.

## Conventions

- Working name: Fogline (rename freely).
- Keep the engine pure and tested; keep MapKit at the edges.
- Start at the current milestone; don't skip the validation gates.
