import Foundation

class PhotosServiceModel: ObservableObject, PhotosService {
    func listAlbums() async throws -> [OneDriveAlbum] {
        preconditionFailure("PhotosServiceModel.listAlbums() must be overridden")
    }

    func probeAlbumUsablePhotoCountFirstPage(albumId: String) async throws -> Int {
        preconditionFailure("PhotosServiceModel.probeAlbumUsablePhotoCountFirstPage() must be overridden")
    }

    func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem] {
        preconditionFailure("PhotosServiceModel.searchPhotos(inAlbumId:) must be overridden")
    }

    func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum? {
        preconditionFailure("PhotosServiceModel.verifyAlbumExists(albumId:) must be overridden")
    }

    func downloadImageData(for item: MediaItem) async throws -> Data {
        preconditionFailure("PhotosServiceModel.downloadImageData(for:) must be overridden")
    }

#if DEBUG
    func debugProbeAlbumListing() async -> String { "" }
#endif
}

final class UITestPhotosService: PhotosServiceModel {
    enum PhotosMode: String {
        case normal = "normal"
        case listAlbumsFailOnce = "listAlbumsFailOnce"
        case listAlbumsAlwaysFail = "listAlbumsAlwaysFail"
    }

    struct Configuration {
        var mode: PhotosMode = .normal
    }

    enum UITestPhotosError: LocalizedError {
        case listAlbumsFailed

        var errorDescription: String? {
            switch self {
            case .listAlbumsFailed:
                return "UI Test: listAlbums failed."
            }
        }
    }

    private let config: Configuration
    private var listAlbumsCallCount: Int = 0

    init(config: Configuration = Configuration()) {
        self.config = config
        super.init()
    }

    private static let albums: [OneDriveAlbum] = [
        OneDriveAlbum(
            id: "uitest-album-1",
            webUrl: URL(string: "https://photos.onedrive.com/?uitest=1&album=1"),
            name: "UI Test Album 1"
        ),
        OneDriveAlbum(
            id: "uitest-album-2",
            webUrl: URL(string: "https://photos.onedrive.com/?uitest=1&album=2"),
            name: "UI Test Album 2"
        ),
    ]

    private static let items: [MediaItem] = [
        MediaItem(
            id: "uitest-item-1",
            downloadUrl: nil,
            pixelWidth: 4000,
            pixelHeight: 3000,
            name: "UI Test Photo 1.png",
            mimeType: "image/png",
            cTag: "c1"
        ),
        MediaItem(
            id: "uitest-item-2",
            downloadUrl: nil,
            pixelWidth: 5120,
            pixelHeight: 2880,
            name: "UI Test Photo 2.png",
            mimeType: "image/png",
            cTag: "c2"
        ),
    ]

    // 1×1 transparent PNG.
    private static let imageData: Data = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6X0mXcAAAAASUVORK5CYII="
    )!

    override func listAlbums() async throws -> [OneDriveAlbum] {
        listAlbumsCallCount += 1
        switch config.mode {
        case .normal:
            return Self.albums
        case .listAlbumsFailOnce:
            if listAlbumsCallCount == 1 { throw UITestPhotosError.listAlbumsFailed }
            return Self.albums
        case .listAlbumsAlwaysFail:
            throw UITestPhotosError.listAlbumsFailed
        }
    }

    override func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum? {
        Self.albums.first(where: { $0.id == albumId })
    }

    override func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem] {
        Self.items
    }

    override func probeAlbumUsablePhotoCountFirstPage(albumId: String) async throws -> Int {
        Self.items.count
    }

    override func downloadImageData(for item: MediaItem) async throws -> Data {
        Self.imageData
    }

#if DEBUG
    override func debugProbeAlbumListing() async -> String {
        "UI Test: debug probe unavailable (fixture mode)."
    }
#endif
}
