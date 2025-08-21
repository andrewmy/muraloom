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
    let mediaItems: [MediaItem]
    let nextPageToken: String?
}

// For creating album
struct NewAlbum: Encodable {
    let title: String
}

struct CreateAlbumResponse: Decodable {
    let album: GooglePhotosAlbum // Re-using GooglePhotosAlbum struct
}

class GooglePhotosService: ObservableObject { // Added ObservableObject
    private let authService: GoogleAuthService // Dependency injection for auth service
    private let baseURL = "https://photoslibrary.googleapis.com/v1"

    init(authService: GoogleAuthService) {
        self.authService = authService
    }

    // Removed listAlbums()

    func createAppAlbum(albumName: String) async throws -> GooglePhotosAlbum {
        guard let user = await authService.user else {
            throw GooglePhotosServiceError.notAuthenticated
        }

        guard let accessToken = try await user.refreshTokensIfNeeded().accessToken.tokenString else {
            throw GooglePhotosServiceError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/albums") else {
            throw GooglePhotosServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let newAlbum = NewAlbum(title: albumName)
        request.httpBody = try JSONEncoder().encode(newAlbum)

        print("DEBUG: Creating album URL: \(url.absoluteString)")
        print("DEBUG: Creating album Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "N/A")")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            print("DEBUG: Create Album Error Response: \(responseBody)")
            throw GooglePhotosServiceError.networkError(statusCode: statusCode, response: responseBody)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let createAlbumResponse = try decoder.decode(CreateAlbumResponse.self, from: data)
            return createAlbumResponse.album
        } catch {
            print("DEBUG: Decoding Error Create Album: \(error.localizedDescription)")
            throw GooglePhotosServiceError.decodingError(error)
        }
    }
    
    func searchPhotos(in albumId: String) async throws -> [MediaItem] {
        guard let user = await authService.user else {
            throw GooglePhotosServiceError.notAuthenticated
        }

        guard let accessToken = try await user.refreshTokensIfNeeded().accessToken.tokenString else {
            throw GooglePhotosServiceError.notAuthenticated
        }

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

        print("DEBUG: Requesting URL for search: \(url.absoluteString)")
        print("DEBUG: Request Body for search: \(String(data: request.httpBody!, encoding: .utf8) ?? "N/A")")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            print("DEBUG: Network Error Response for search: \(responseBody)")
            throw GooglePhotosServiceError.networkError(statusCode: statusCode, response: responseBody)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let searchResponse = try decoder.decode(SearchMediaItemsResponse.self, from: data)
            return searchResponse.mediaItems
        } catch {
            print("DEBUG: Decoding Error for search: \(error.localizedDescription)")
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
