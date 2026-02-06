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

final class OneDrivePhotosService: ObservableObject, PhotosService {
    private let authService: any OneDriveAccessTokenProviding
    private let session: URLSession
    private let baseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    init(authService: any OneDriveAccessTokenProviding, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func listAlbums() async throws -> [OneDriveAlbum] {
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

    func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum? {
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

    func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem] {
        let expandedChildren: DriveItemExpandedChildrenResponse = try await get(
            "/me/drive/items/\(albumId)",
            query: [
                .init(name: "$select", value: "id"),
                .init(
                    name: "$expand",
                    value: "children($select=id,name,webUrl,file,image,photo)"
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

    func probeAlbumUsablePhotoCountFirstPage(albumId: String) async throws -> Int {
        let expandedChildren: DriveItemExpandedChildrenResponse = try await get(
            "/me/drive/items/\(albumId)",
            query: [
                .init(name: "$select", value: "id"),
                .init(
                    name: "$expand",
                    // Note: for DriveItem children, Graph only supports $select/$expand inside $expand options.
                    // $top in expand options yields a 400 (invalidRequest).
                    value: "children($select=id,name,file,image,photo)"
                ),
            ]
        )
        return Self.mediaItems(from: expandedChildren.children ?? []).count
    }

    func downloadImageData(for item: MediaItem) async throws -> Data {
        if isRawStillImage(item) {
            if let thumb = try await downloadLargestThumbnailData(itemId: item.id) {
                return thumb
            }

            let ext = item.name.flatMap { ($0 as NSString).pathExtension.lowercased() }
            let extLabel = (ext?.isEmpty == false) ? ".\(ext!)" : "RAW"
            throw NSError(
                domain: "OneDrivePhotosService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "RAW photos (\(extLabel)) aren’t directly wallpaper-safe. Couldn’t fetch a OneDrive preview thumbnail; export to JPEG/HEIC or wait for OneDrive to generate previews."]
            )
        }

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

    private func isRawStillImage(_ item: MediaItem) -> Bool {
        let name = item.name?.lowercased() ?? ""
        return name.hasSuffix(".arw")
            || name.hasSuffix(".cr2")
            || name.hasSuffix(".nef")
            || name.hasSuffix(".dng")
            || name.hasSuffix(".raf")
            || name.hasSuffix(".orf")
            || name.hasSuffix(".rw2")
    }

    private func downloadLargestThumbnailData(itemId: String) async throws -> Data? {
        let response: ThumbnailsResponse = try await get("/me/drive/items/\(itemId)/thumbnails")
        guard let first = response.value.first else { return nil }

        let candidates: [Thumbnail] = [first.large, first.medium, first.small].compactMap { $0 }
        guard let best = candidates.max(by: { a, b in
            let aArea = (a.width ?? 0) * (a.height ?? 0)
            let bArea = (b.width ?? 0) * (b.height ?? 0)
            if aArea != bArea { return aArea < bArea }
            return (a.url ?? "") < (b.url ?? "")
        }) else { return nil }

        guard let urlString = best.url, let url = URL(string: urlString) else { return nil }

        let (data, resp) = try await session.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OneDriveGraphError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
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
        driveItems.compactMap { item in
            let mime = item.file?.mimeType ?? ""
            let lowercasedName = item.name?.lowercased() ?? ""
            let isImage =
                mime.hasPrefix("image/")
                || item.image != nil
                || item.photo != nil
                || lowercasedName.hasSuffix(".jpg")
                || lowercasedName.hasSuffix(".jpeg")
                || lowercasedName.hasSuffix(".png")
                || lowercasedName.hasSuffix(".heic")
                || lowercasedName.hasSuffix(".arw")
                || lowercasedName.hasSuffix(".dng")
            guard isImage else { return nil }
            return MediaItem(
                id: item.id,
                downloadUrl: item.downloadUrl.flatMap(URL.init(string:)),
                pixelWidth: item.image?.width,
                pixelHeight: item.image?.height,
                name: item.name,
                mimeType: item.file?.mimeType
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
    func debugProbeAlbumListing() async -> String {
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

private struct ThumbnailsResponse: Decodable {
    let value: [ThumbnailSet]
}

private struct ThumbnailSet: Decodable {
    let id: String?
    let small: Thumbnail?
    let medium: Thumbnail?
    let large: Thumbnail?
}

private struct Thumbnail: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}

private struct DriveItem: Decodable {
    let id: String
    let name: String?
    let webUrl: URL?
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
