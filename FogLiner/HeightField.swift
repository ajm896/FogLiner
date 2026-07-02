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

