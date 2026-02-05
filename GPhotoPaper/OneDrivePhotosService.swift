import Foundation

enum OneDriveGraphError: Error, LocalizedError {
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let status, _):
            return "Graph HTTP \(status)."
        }
    }
}

protocol OneDriveAccessTokenProviding {
    func validAccessToken() async throws -> String
}

extension OneDriveAuthService: OneDriveAccessTokenProviding {}

final class OneDrivePhotosService: ObservableObject, PhotosService {
    private let authService: any OneDriveAccessTokenProviding
    private let session: URLSession
    private let baseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    init(authService: any OneDriveAccessTokenProviding, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func listAlbums() async throws -> [OneDriveAlbum] {
        let path = "/me/drive/bundles"
        var components = URLComponents(url: graphURL(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "$filter", value: "bundle/album ne null"),
            .init(name: "$select", value: "id,name,webUrl,bundle"),
        ]

        return try await pagedDriveItems(startURL: components.url!) { page in
            page.value
                .filter { $0.bundle?.album != nil }
                .map { OneDriveAlbum(id: $0.id, webUrl: $0.webUrl, name: $0.name) }
        }
    }

    func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum? {
        let item: DriveItem = try await get(
            "/me/drive/items/\(albumId)",
            query: [
                .init(name: "$select", value: "id,name,webUrl,bundle"),
            ]
        )
        guard item.bundle?.album != nil else { return nil }
        return OneDriveAlbum(id: item.id, webUrl: item.webUrl, name: item.name)
    }

    func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem] {
        let expandedChildren: DriveItemExpandedChildrenResponse = try await get(
            "/me/drive/items/\(albumId)",
            query: [
                .init(name: "$select", value: "id"),
                .init(
                    name: "$expand",
                    value: "children($select=id,name,webUrl,file,image,@microsoft.graph.downloadUrl)"
                ),
            ]
        )

        var results = Self.mediaItems(from: expandedChildren.children ?? [])

        if let nextLink = expandedChildren.childrenNextLink, let nextURL = URL(string: nextLink) {
            let additional = try await pagedDriveItems(startURL: nextURL) { page in
                Self.mediaItems(from: page.value)
            }
            results.append(contentsOf: additional)
        }

        return results
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: graphURL(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let accessToken = try await authService.validAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200...299).contains(status) {
            throw OneDriveGraphError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func graphURL(_ path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(trimmed)
    }

    private static func mediaItems(from driveItems: [DriveItem]) -> [MediaItem] {
        driveItems.compactMap { item in
            guard let download = item.downloadUrl, let downloadURL = URL(string: download) else {
                return nil
            }
            if let mime = item.file?.mimeType, mime.hasPrefix("image/") == false, item.image == nil {
                return nil
            }
            return MediaItem(
                id: item.id,
                downloadUrl: downloadURL,
                pixelWidth: item.image?.width,
                pixelHeight: item.image?.height
            )
        }
    }

    private func pagedDriveItems<U>(
        startURL: URL,
        map: @escaping (DriveItemListResponse) -> [U]
    ) async throws -> [U] {
        var results: [U] = []
        var nextURL: URL? = startURL

        while let url = nextURL {
            let accessToken = try await authService.validAccessToken()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            if let status = http?.statusCode, !(200...299).contains(status) {
                throw OneDriveGraphError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
            }

            let decoded = try JSONDecoder().decode(DriveItemListResponse.self, from: data)
            results.append(contentsOf: map(decoded))
            nextURL = decoded.nextLink.flatMap(URL.init(string:))
        }

        return results
    }
}

private struct DriveItemListResponse: Decodable {
    let value: [DriveItem]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

private struct DriveItem: Decodable {
    let id: String
    let name: String?
    let webUrl: URL?
    let bundle: BundleFacet?
    let file: FileFacet?
    let image: ImageFacet?
    let downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case webUrl
        case bundle
        case file
        case image
        case downloadUrl = "@microsoft.graph.downloadUrl"
    }
}

private struct BundleFacet: Decodable {
    let album: AlbumFacet?
}

private struct AlbumFacet: Decodable {}

private struct FileFacet: Decodable {
    let mimeType: String?
}

private struct ImageFacet: Decodable {
    let width: Int?
    let height: Int?
}

private struct DriveItemExpandedChildrenResponse: Decodable {
    let children: [DriveItem]?
    let childrenNextLink: String?

    enum CodingKeys: String, CodingKey {
        case children
        case childrenNextLink = "children@odata.nextLink"
    }
}
