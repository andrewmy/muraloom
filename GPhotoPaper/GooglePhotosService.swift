import Foundation
import GoogleSignIn // For GIDGoogleUser and access token

// Re-adding GooglePhotosAlbum struct
struct GooglePhotosAlbum: Identifiable, Decodable {
    let id: String
    let title: String
    let productUrl: URL?
    let mediaItemsCount: String? // Number of media items in the album.
}

// Add MediaItem related structs for searchPhotos
struct MediaItem: Identifiable, Decodable {
    let id: String
    let productUrl: URL
    let baseUrl: URL
    let mimeType: String
    let mediaMetadata: MediaMetadata
    let filename: String
}

struct MediaMetadata: Decodable {
    let creationTime: String
    let width: String
    let height: String
    let photo: PhotoMetadata?
    let video: VideoMetadata?
}

struct PhotoMetadata: Decodable {
    let cameraMake: String?
    let cameraModel: String?
    let focalLength: Double?
    let apertureFNumber: Double?
    let isoEquivalent: Int?
    let exposureTime: String?
}

struct VideoMetadata: Decodable {
    let cameraMake: String?
    let cameraModel: String?
    let fps: Double?
    let status: String?
}

struct SearchMediaItemsResponse: Decodable {
    let mediaItems: [MediaItem]?
    let nextPageToken: String?
}

// For creating album
struct NewAlbumContent: Encodable {
    let title: String
}

struct NewAlbum: Encodable {
    let album: NewAlbumContent

    enum CodingKeys: String, CodingKey {
        case album
    }
}

struct ListAlbumsResponse: Decodable {
    let albums: [GooglePhotosAlbum]?
    let nextPageToken: String?
}

class GooglePhotosService: ObservableObject {
    private let authService: GoogleAuthService
    private let settings: SettingsModel
    private let baseURL = "https://photoslibrary.googleapis.com/v1"

    init(authService: GoogleAuthService, settings: SettingsModel) {
        self.authService = authService
        self.settings = settings
    }

    // Removed listAlbums()

    func createAppAlbum(albumName: String) async throws -> GooglePhotosAlbum {
        guard let user = await authService.user else {
            throw GooglePhotosServiceError.notAuthenticated
        }

        let accessToken = try await user.refreshTokensIfNeeded().accessToken.tokenString

        guard let url = URL(string: "\(baseURL)/albums") else {
            throw GooglePhotosServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let newAlbum = NewAlbum(album: NewAlbumContent(title: albumName))
        request.httpBody = try JSONEncoder().encode(newAlbum)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            throw GooglePhotosServiceError.networkError(statusCode: statusCode, response: responseBody)
        }
        let responseBody = String(data: data, encoding: .utf8) ?? "N/A"

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let album = try decoder.decode(GooglePhotosAlbum.self, from: data)
            return album
        } catch {
            throw GooglePhotosServiceError.decodingError(error)
        }
    }

    func listAlbums(albumName: String? = nil) async throws -> [GooglePhotosAlbum] {
        guard let user = await authService.user else {
            throw GooglePhotosServiceError.notAuthenticated
        }

        let accessToken = try await user.refreshTokensIfNeeded().accessToken.tokenString

        guard let url = URL(string: "\(baseURL)/albums") else {
            throw GooglePhotosServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            throw GooglePhotosServiceError.networkError(statusCode: statusCode, response: responseBody)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let listAlbumsResponse = try decoder.decode(ListAlbumsResponse.self, from: data)
            if let name = albumName {
                return listAlbumsResponse.albums?.filter { $0.title == name } ?? []
            } else {
                return listAlbumsResponse.albums ?? []
            }
        } catch {
            throw GooglePhotosServiceError.decodingError(error)
        }
    }
    
    func searchPhotos(in albumId: String) async throws -> [MediaItem] {
        guard let user = await authService.user else {
            throw GooglePhotosServiceError.notAuthenticated
        }

        let accessToken = try await user.refreshTokensIfNeeded().accessToken.tokenString

        guard let url = URL(string: "\(baseURL)/mediaItems:search") else {
            throw GooglePhotosServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let requestBody: [String: Any] = [
            "albumId": albumId,
            "pageSize": 100 // Request up to 100 media items
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            throw GooglePhotosServiceError.networkError(statusCode: statusCode, response: responseBody)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let searchResponse = try decoder.decode(SearchMediaItemsResponse.self, from: data)
            var mediaItems = searchResponse.mediaItems ?? []
            
            if settings.horizontalPhotosOnly {
                mediaItems = mediaItems.filter { item in
                    guard let width = Double(item.mediaMetadata.width),
                          let height = Double(item.mediaMetadata.height) else { return false }
                    return width > height
                }
            }
            
            return mediaItems
        } catch {
            throw GooglePhotosServiceError.decodingError(error)
        }
    }
}

enum GooglePhotosServiceError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case networkError(statusCode: Int, response: String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated with Google Photos."
        case .invalidURL:
            return "Invalid URL for Google Photos API."
        case .networkError(let statusCode, let response):
            return "Network error: Status Code \(statusCode), Response: \(response)"
        case .decodingError(let error):
            return "Failed to decode API response: \(error.localizedDescription)"
        }
    }
}
