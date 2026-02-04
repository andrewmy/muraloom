import Foundation

enum OneDriveGraphError: Error, LocalizedError {
    case notSignedIn
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in."
        case .httpError(let status, _):
            return "Graph HTTP \(status)."
        }
    }
}

final class OneDrivePhotosService: ObservableObject, PhotosService {
    private let authService: OneDriveAuthService
    private let session: URLSession
    private let baseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    init(authService: OneDriveAuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func verifyFolderExists(folderId: String) async throws -> OneDriveFolder? {
        let item: DriveItem = try await get(
            "/me/drive/items/\(folderId)",
            query: [
                .init(name: "$select", value: "id,name,webUrl,folder"),
            ]
        )
        guard item.folder != nil else { return nil }
        return OneDriveFolder(id: item.id, webUrl: item.webUrl, name: item.name)
    }

    func listFoldersInRoot() async throws -> [OneDriveFolder] {
        try await listFolders(childrenOfItemId: nil)
    }

    func listFolders(childrenOfItemId itemId: String?) async throws -> [OneDriveFolder] {
        let path: String
        if let itemId, !itemId.isEmpty {
            path = "/me/drive/items/\(itemId)/children"
        } else {
            path = "/me/drive/root/children"
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "$select", value: "id,name,webUrl,folder"),
        ]
        return try await pagedDriveItems(startURL: components.url!) { page in
            page.value
                .filter { $0.folder != nil }
                .map { OneDriveFolder(id: $0.id, webUrl: $0.webUrl, name: $0.name) }
        }
    }

    func searchPhotos(in folderId: String) async throws -> [MediaItem] {
        let path = "/me/drive/items/\(folderId)/children"
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "$select", value: "id,name,webUrl,file,image,@microsoft.graph.downloadUrl"),
        ]

        return try await pagedDriveItems(startURL: components.url!) { page in
            page.value.compactMap { item in
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
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
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
    let folder: FolderFacet?
    let file: FileFacet?
    let image: ImageFacet?
    let downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case webUrl
        case folder
        case file
        case image
        case downloadUrl = "@microsoft.graph.downloadUrl"
    }
}

private struct FolderFacet: Decodable {}

private struct FileFacet: Decodable {
    let mimeType: String?
}

private struct ImageFacet: Decodable {
    let width: Int?
    let height: Int?
}
