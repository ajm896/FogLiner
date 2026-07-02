//
//  TileSource.swift
//  FogLiner
//
//  Created by Albert Morris on 6/26/26.
//

import Foundation
import ImageIO
import Playgrounds

nonisolated struct TileKey: Hashable, Sendable {
    let z, x, y: Int

    init(_ z: Int, _ x: Int, _ y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }

    func toPath() -> String {
        "\(z)/\(x)/\(y)"
    }

    func toURL(with baseURL: String) -> URL {
        URL(string: "\(baseURL)\(toPath()).png")!
    }

}

actor TileSource<Payload: Sendable> {
    private let urlTemplate: String
    private let decode: @Sendable (Data, TileKey) throws -> Payload
    private let session: URLSession
    private let cacheDir: URL

    init(
        urlTemplate: String =
            "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/",
        session: URLSession = .shared,
        cacheDir: URL = .cachesDirectory.appending(path: "tiles"),
        decode: @escaping @Sendable (Data, TileKey) throws -> Payload
    ) {
        self.urlTemplate = urlTemplate
        self.session = session
        self.cacheDir = cacheDir
        self.decode = decode
    }

    func tile(_ key: TileKey) async throws -> Payload {
        let data = try await self.tileData(z: key.z, x: key.x, y: key.y)
        return try self.decode(data, key)
    }

    enum TileError: Error { case badStatus(Int) }

    func cacheURL(z: Int, x: Int, y: Int) -> URL {
        let url = cacheDir.appending(path: "\(z)/\(x)/\(y).png")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return url
    }

    func tileData(z: Int, x: Int, y: Int) async throws -> Data {
        let cache = cacheURL(z: z, x: x, y: y)
        if let hit = try? Data(contentsOf: cache) { return hit }
        let remote = URL(string: "\(urlTemplate)\(z)/\(x)/\(y).png")!
        let (data, response) = try await self.session.data(from: remote)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            throw TileError.badStatus(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
        try data.write(to: cache)
        return data
    }
}

enum ZoomDir {
    case In
    case Out
}


// 15/8831/12927
