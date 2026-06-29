//
//  Fixtures.swift
//  FogLiner
//
//  Created by Albert Morris on 6/26/26.
//


import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FogLiner

enum Fixtures {
    // M1 validation gate — verified constants (see CLAUDE.md). Do NOT use 1920 m.
    static let coldMountainLat = 35.410
    static let coldMountainLon = -82.856
    static let coldMountainMeters = 1838.0
    static let toleranceMeters = 15.0

    /// Inverse Terrarium encode: metres -> (R,G,B). Exact inverse of (R*256+G+B/256)-32768.
    static func encode(_ meters: Double) -> (UInt8, UInt8, UInt8) {
        let v = meters + 32768.0                       // positive, 16.8 fixed-point
        let r = Int(v / 256) & 0xFF
        let g = Int(v.rounded(.down)) & 0xFF
        let b = Int(((v - v.rounded(.down)) * 256).rounded(.down)) & 0xFF
        return (UInt8(r), UInt8(g), UInt8(b))
    }

    /// Build a lossless Terrarium-encoded PNG from a row-major elevation grid.
    /// Encodes with the same color space the decoder uses, so a clean round-trip
    /// confirms CG isn't color-managing the data channels.
    static func terrariumPNG(elevations: [Double], width: Int, height: Int) -> Data {
        precondition(elevations.count == width * height)
        var px = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let (r, g, b) = encode(elevations[i])
            px[i*4] = r; px[i*4+1] = g; px[i*4+2] = b; px[i*4+3] = 255
        }
        let ctx = px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        }
        let image = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    static func makeTempDir() -> URL {
        let dir = URL.temporaryDirectory.appending(path: "FogLinerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Intercepts URLSession traffic so cache tests are deterministic and offline.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub { let data: Data; let status: Int }
    nonisolated(unsafe) static var stub: Stub?
    nonisolated(unsafe) static var hitCount = 0
    static func reset() { stub = nil; hitCount = 0 }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.hitCount += 1
        guard let s = Self.stub, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let resp = HTTPURLResponse(url: url, statusCode: s.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: s.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension URLSession {
    static func stubbed() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}


