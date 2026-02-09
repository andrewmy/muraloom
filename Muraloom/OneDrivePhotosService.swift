import Foundation

enum OneDriveGraphError: Error, LocalizedError {
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Graph HTTP \(status)."
            }

            let maxChars = 800
            let prefix = String(trimmed.prefix(maxChars))
            if trimmed.count > maxChars {
                return "Graph HTTP \(status): \(prefix)…"
            }
            return "Graph HTTP \(status): \(prefix)"
        }
    }
}

protocol OneDriveAccessTokenProviding {
    func validAccessToken() async throws -> String
}

extension OneDriveAuthService: OneDriveAccessTokenProviding {}

final class OneDrivePhotosService: PhotosServiceModel {
    private let authService: any OneDriveAccessTokenProviding
    private let session: URLSession
    private let baseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    init(authService: any OneDriveAccessTokenProviding, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
        super.init()
    }

    override func listAlbums() async throws -> [OneDriveAlbum] {
        let filtered = try await listBundlesAsDriveItems(filterToAlbums: true)
        if !filtered.isEmpty {
            return filtered
                .filter(Self.isAlbumCandidateStrict)
                .map { OneDriveAlbum(id: $0.id, webUrl: $0.webUrl, name: $0.name) }
        }

        // Some accounts return empty results when filtering by bundle album; retry unfiltered.
        let unfiltered = try await listBundlesAsDriveItems(filterToAlbums: false)
        return unfiltered
            .filter(Self.isAlbumCandidateStrict)
            .map { OneDriveAlbum(id: $0.id, webUrl: $0.webUrl, name: $0.name) }
    }

    override func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum? {
        do {
            let bundleItem: DriveItem = try await get(
                "/me/drive/bundles/\(albumId)",
                query: [
                    .init(name: "$select", value: "id,name,webUrl,bundle"),
                ]
            )
            if Self.isAlbumCandidateStrict(bundleItem) || bundleItem.bundle != nil {
                return OneDriveAlbum(id: bundleItem.id, webUrl: bundleItem.webUrl, name: bundleItem.name)
            }
        } catch {
            // Fall through to item lookup (some IDs aren't resolvable via the bundles endpoint).
        }

        let item: DriveItem = try await get(
            "/me/drive/items/\(albumId)",
            query: [
                .init(name: "$select", value: "id,name,webUrl,bundle,folder"),
            ]
        )

        let isContainer = item.bundle != nil || item.folder != nil || Self.isAlbumCandidateStrict(item)
        guard isContainer else { return nil }
        return OneDriveAlbum(id: item.id, webUrl: item.webUrl, name: item.name)
    }

    override func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem] {
        let expandedChildren: DriveItemExpandedChildrenResponse = try await get(
            "/me/drive/items/\(albumId)",
            query: [
                .init(name: "$select", value: "id"),
                .init(
                    name: "$expand",
                    value: "children($select=id,name,webUrl,file,image,photo,cTag)"
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

    override func probeAlbumUsablePhotoCountFirstPage(albumId: String) async throws -> Int {
        let expandedChildren: DriveItemExpandedChildrenResponse = try await get(
            "/me/drive/items/\(albumId)",
            query: [
                .init(name: "$select", value: "id"),
                .init(
                    name: "$expand",
                    // Note: for DriveItem children, Graph only supports $select/$expand inside $expand options.
                    // $top in expand options yields a 400 (invalidRequest).
                    value: "children($select=id,name,file,image,photo,cTag)"
                ),
            ]
        )
        return Self.mediaItems(from: expandedChildren.children ?? []).count
    }

    override func downloadImageData(for item: MediaItem) async throws -> Data {
        if let url = item.downloadUrl {
            let (data, response) = try await session.data(from: url)
            let http = response as? HTTPURLResponse
            if let status = http?.statusCode, !(200...299).contains(status) {
                throw OneDriveGraphError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
            }
            return data
        }

        let accessToken = try await authService.validAccessToken()
        var request = URLRequest(url: graphURL("/me/drive/items/\(item.id)/content"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200...299).contains(status) {
            throw OneDriveGraphError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        return data
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

    private func listBundlesAsDriveItems(filterToAlbums: Bool) async throws -> [DriveItem] {
        func url(for path: String) -> URL {
            var components = URLComponents(url: graphURL(path), resolvingAgainstBaseURL: false)!
            var items: [URLQueryItem] = []
            if filterToAlbums {
                items.append(.init(name: "$filter", value: "bundle/album ne null"))
            }
            items.append(.init(name: "$select", value: "id,name,webUrl,bundle"))
            components.queryItems = items
            return components.url!
        }

        // Prefer an explicit drive-id form (seems to be the most reliable), then fall back.
        if let driveId = try? await currentDriveId() {
            let byId = try await pagedDriveItems(startURL: url(for: "/drives/\(driveId)/bundles")) { page in page.value }
            if !byId.isEmpty { return byId }
        }

        let driveResults = try await pagedDriveItems(startURL: url(for: "/drive/bundles")) { page in page.value }
        if !driveResults.isEmpty { return driveResults }

        return try await pagedDriveItems(startURL: url(for: "/me/drive/bundles")) { page in page.value }
    }

    private func graphURL(_ path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(trimmed)
    }

    private func currentDriveId() async throws -> String {
        struct DriveResponse: Decodable { let id: String }
        let drive: DriveResponse = try await get(
            "/me/drive",
            query: [
                .init(name: "$select", value: "id"),
            ]
        )
        return drive.id
    }

    private static func mediaItems(from driveItems: [DriveItem]) -> [MediaItem] {
        let supportsRaw = LibRawDecoder.isAvailable()
        return driveItems.compactMap { item -> MediaItem? in
            let mime = item.file?.mimeType ?? ""
            let lowercasedName = item.name?.lowercased() ?? ""

            let isRaw =
                lowercasedName.hasSuffix(".arw")
                || lowercasedName.hasSuffix(".dng")
                || lowercasedName.hasSuffix(".cr2")
                || lowercasedName.hasSuffix(".nef")
                || lowercasedName.hasSuffix(".raf")
                || lowercasedName.hasSuffix(".orf")
                || lowercasedName.hasSuffix(".rw2")

            let isImage =
                mime.hasPrefix("image/")
                || item.image != nil
                || item.photo != nil
                || isRaw
                || lowercasedName.hasSuffix(".jpg")
                || lowercasedName.hasSuffix(".jpeg")
                || lowercasedName.hasSuffix(".png")
                || lowercasedName.hasSuffix(".heic")

            guard isImage, (isRaw == false || supportsRaw) else { return nil }
            return MediaItem(
                id: item.id,
                downloadUrl: item.downloadUrl.flatMap(URL.init(string:)),
                pixelWidth: item.image?.width,
                pixelHeight: item.image?.height,
                name: item.name,
                mimeType: item.file?.mimeType,
                cTag: item.cTag
            )
        }
    }

    private static func isAlbumCandidateStrict(_ item: DriveItem) -> Bool {
        // Prefer signals that match OneDrive Photos “Albums”.
        if item.bundle?.album != nil { return true }
        if let url = item.webUrl, url.host == "photos.onedrive.com" { return true }
        return false
    }

#if DEBUG
    override func debugProbeAlbumListing() async -> String {
        struct ProbeResponse {
            let label: String
            let status: Int?
            let valueCount: Int?
            let bodyPrefix: String
            let error: String?
        }

        func bodyPrefix(from data: Data) -> String {
            let str = String(data: data, encoding: .utf8) ?? ""
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxChars = 1200
            let prefix = String(trimmed.prefix(maxChars))
            return trimmed.count > maxChars ? "\(prefix)…" : prefix
        }

        func rawGet(url: URL) async -> ProbeResponse {
            do {
                let accessToken = try await authService.validAccessToken()
                var request = URLRequest(url: url)
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode

                var decodedCount: Int?
                if let status, (200...299).contains(status),
                   let decoded = try? JSONDecoder().decode(DriveItemListResponse.self, from: data) {
                    decodedCount = decoded.value.count
                }

                return ProbeResponse(
                    label: url.path + (url.query.map { "?\($0)" } ?? ""),
                    status: status,
                    valueCount: decodedCount,
                    bodyPrefix: bodyPrefix(from: data),
                    error: nil
                )
            } catch {
                return ProbeResponse(
                    label: url.absoluteString,
                    status: nil,
                    valueCount: nil,
                    bodyPrefix: "",
                    error: error.localizedDescription
                )
            }
        }

        func format(_ probe: ProbeResponse) -> String {
            var lines: [String] = ["• \(probe.label)"]
            if let status = probe.status { lines.append("  status: \(status)") }
            if let valueCount = probe.valueCount { lines.append("  value.count: \(valueCount)") }
            if let error = probe.error, !error.isEmpty { lines.append("  error: \(error)") }
            if !probe.bodyPrefix.isEmpty { lines.append("  body: \(probe.bodyPrefix)") }
            return lines.joined(separator: "\n")
        }

        let driveInfoURL: URL = {
            var components = URLComponents(url: graphURL("/me/drive"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                .init(name: "$select", value: "id,driveType,owner,webUrl"),
            ]
            return components.url!
        }()

        var probes: [ProbeResponse] = [await rawGet(url: driveInfoURL)]

        let driveId = (try? await currentDriveId())
        if let driveId {
            for (path, addAlbumFilter) in [
                ("/drives/\(driveId)/bundles", false),
                ("/drives/\(driveId)/bundles", true),
            ] {
                var components = URLComponents(url: graphURL(path), resolvingAgainstBaseURL: false)!
                var items: [URLQueryItem] = [
                    .init(name: "$select", value: "id,name,webUrl,bundle"),
                    .init(name: "$top", value: "10"),
                ]
                if addAlbumFilter {
                    items.insert(.init(name: "$filter", value: "bundle/album ne null"), at: 0)
                }
                components.queryItems = items
                probes.append(await rawGet(url: components.url!))
            }
        }

        for ep in ["/drive/bundles", "/me/drive/bundles"] {
            var components = URLComponents(url: graphURL(ep), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                .init(name: "$select", value: "id,name,webUrl,bundle"),
                .init(name: "$top", value: "10"),
            ]
            probes.append(await rawGet(url: components.url!))
        }

        return (["OneDrive albums probe (no tokens shown):"]
            + probes.map(format)).joined(separator: "\n")
    }
#endif

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
    let cTag: String?
    let bundle: BundleFacet?
    let folder: FolderFacet?
    let file: FileFacet?
    let image: ImageFacet?
    let photo: PhotoFacet?
    let downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case webUrl
        case cTag
        case bundle
        case folder
        case file
        case image
        case photo
        case downloadUrl = "@microsoft.graph.downloadUrl"
    }
}

private struct BundleFacet: Decodable {
    let album: AlbumFacet?
    let childCount: Int?
}

private struct AlbumFacet: Decodable {}

private struct FolderFacet: Decodable {
    let childCount: Int?
}

private struct FileFacet: Decodable {
    let mimeType: String?
}

private struct ImageFacet: Decodable {
    let width: Int?
    let height: Int?
}

private struct PhotoFacet: Decodable {}

private struct DriveItemExpandedChildrenResponse: Decodable {
    let children: [DriveItem]?
    let childrenNextLink: String?

    enum CodingKeys: String, CodingKey {
        case children
        case childrenNextLink = "children@odata.nextLink"
    }
}
