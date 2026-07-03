//
//  HeightField.swift
//  FogLiner
//
//  Created by Albert Morris on 6/26/26.
//

import CoreImage
import Foundation
import ImageIO
import Playgrounds
import SwiftUI

nonisolated struct HeightField {
    private let key: TileKey
    private let tileHeightMap: [Double]

    let width: Int
    let height: Int

    // Add (orientation note: whether row 0 is N or S is unverified until the gate;
    // the decode test is orientation-agnostic since it reads back the same (col,row) it wrote):
    func elevation(col: Int, row: Int) -> Double {
        tileHeightMap[row * width + col]
    }

    /// Bilinearly-interpolated elevation at an arbitrary (lat, lon) inside this tile.
    ///
    /// Pixel position is derived from this tile's own `key`, so no external tile-cover
    /// lookup is needed. Points outside the tile's pixel bounds (including points near
    /// an edge whose interpolation would reach into a neighboring tile) are clamped to
    /// the tile's own edge pixels rather than fetching a neighbor — a small, deliberate
    /// v1 approximation confined to the last fraction of a pixel at tile boundaries.
    func elevation(atLat lat: Double, lon: Double) -> Double {
        let (px, py) = key.fractionalPixel(lat: lat, lon: lon, tileSize: Double(width))
        let maxCol = Double(width - 1)
        let maxRow = Double(height - 1)
        let x = min(max(px - 0.5, 0), maxCol)
        let y = min(max(py - 0.5, 0), maxRow)

        let col0 = Int(x)
        let row0 = Int(y)
        let col1 = min(col0 + 1, width - 1)
        let row1 = min(row0 + 1, height - 1)
        let fx = x - Double(col0)
        let fy = y - Double(row0)

        let top = elevation(col: col0, row: row0) * (1 - fx) + elevation(col: col1, row: row0) * fx
        let bottom = elevation(col: col0, row: row1) * (1 - fx) + elevation(col: col1, row: row1) * fx
        return top * (1 - fy) + bottom * fy
    }

    enum DecodeError: Error {
        case notAnImage
        case contextCreationFailed
    }

    /// Decode a Terrarium PNG tile into a heightfield.
    /// Each pixel maps to metres via `(R*256 + G + B/256) - 32768`.
    init(key: TileKey, from data: Data) throws {
        self.key = key

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw DecodeError.notAnImage
        }

        let width = image.width
        let height = image.height

        // In init(), after computing width/height locally:
        self.width = width
        self.height = height

        let bytesPerRow = width * 4

        // Draw into a known RGBA8 buffer so channel order/precision are predictable.
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard
            let context = pixels.withUnsafeMutableBytes({
                buffer -> CGContext? in
                CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )
            })
        else {
            throw DecodeError.contextCreationFailed
        }
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        var map = [Double](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Double(pixels[i * 4])
            let g = Double(pixels[i * 4 + 1])
            let b = Double(pixels[i * 4 + 2])
            map[i] = (r * 256 + g + b / 256) - 32768
        }
        self.tileHeightMap = map
    }
}

