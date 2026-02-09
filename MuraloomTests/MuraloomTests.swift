//
//  MuraloomTests.swift
//  MuraloomTests
//
//  Created by Andrejs MJ on 21/08/2025.
//

import Testing
import Foundation
@testable import Muraloom

struct MuraloomTests {
    final class TestTokenProvider: OneDriveAccessTokenProviding {
        func validAccessToken() async throws -> String { "test-token" }
    }

    final class MockURLProtocol: URLProtocol {
        static let handlerHeader = "X-Mock-Handler-ID"

        private static let lock = NSLock()
        private static var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

        static func setHandler(
            _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data),
            for id: String
        ) {
            lock.lock()
            handlers[id] = handler
            lock.unlock()
        }

        static func removeHandler(for id: String) {
            lock.lock()
            handlers[id] = nil
            lock.unlock()
        }

        private static func handler(for request: URLRequest) -> ((URLRequest) throws -> (HTTPURLResponse, Data)) {
            guard let id = request.value(forHTTPHeaderField: handlerHeader) else {
                fatalError("Missing \(handlerHeader) header")
            }
            lock.lock()
            let handler = handlers[id]
            lock.unlock()
            guard let handler else {
                fatalError("No handler registered for id \(id)")
            }
            return handler
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let handler = Self.handler(for: request)
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (session: URLSession, handlerId: String) {
        let handlerId = UUID().uuidString
        MockURLProtocol.setHandler(handler, for: handlerId)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [MockURLProtocol.handlerHeader: handlerId]
        return (URLSession(configuration: config), handlerId)
    }

    final class RequestRecorder {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []

        func record(_ request: URLRequest) {
            lock.lock()
            requests.append(request)
            lock.unlock()
        }
    }

    @Test func listAlbumsFiltersToBundleAlbums() async throws {
        let recorder = RequestRecorder()
        let (session, handlerId) = makeSession { request in
            recorder.record(request)

            let json: String
            if request.url?.path.hasSuffix("/me/drive") == true {
                json = """
                { "id": "d1" }
                """
            } else if request.url?.path.hasSuffix("/drives/d1/bundles") == true {
                let isFiltered = request.url?.query?.contains("bundle%2Falbum%20ne%20null") == true
                    || request.url?.query?.contains("bundle/album%20ne%20null") == true
                if isFiltered {
                    json = """
                    {
                      "value": [
                        { "id": "a1", "name": "Album 1", "webUrl": "https://onedrive.example/a1", "bundle": { "album": {} } }
                      ]
                    }
                    """
                } else {
                    json = """
                    {
                      "value": [
                        { "id": "a1", "name": "Album 1", "webUrl": "https://onedrive.example/a1", "bundle": { "album": {} } },
                        { "id": "x1", "name": "Not an album", "webUrl": "https://onedrive.example/x1", "bundle": { } }
                      ]
                    }
                    """
                }
            } else {
                json = """
                { "value": [] }
                """
            }
            let data = Data(json.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        defer { MockURLProtocol.removeHandler(for: handlerId) }

        let service = OneDrivePhotosService(authService: TestTokenProvider(), session: session)
        let albums = try await service.listAlbums()
        #expect(albums.count == 1)
        #expect(albums.first?.id == "a1")
        #expect(recorder.requests.count == 2)
        #expect(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" })
        #expect(recorder.requests.first?.url?.path.hasSuffix("/me/drive") == true)
        #expect(recorder.requests.last?.url?.path.hasSuffix("/drives/d1/bundles") == true)
    }

    @Test func graphErrorDescriptionTrimsAndCapsBody() throws {
        let longBody = String(repeating: "x", count: 1200)
        let error = OneDriveGraphError.httpError(status: 429, body: "  \(longBody)  ")
        let desc = try #require(error.errorDescription)
        #expect(desc.hasPrefix("Graph HTTP 429: "))
        #expect(desc.contains("…"))
        #expect(desc.count < 1000)
    }

    @Test func searchPhotosFiltersToUsableImagesAndOptionallyIncludesRAW() async throws {
        let nextLink = "https://graph.microsoft.com/v1.0/me/drive/items/a1/children?$skiptoken=abc"
        let (session, handlerId) = makeSession { request in
            if request.url?.path.hasSuffix("/me/drive/items/a1") == true {
                let json = """
                {
                  "id": "a1",
                  "children": [
                    { "id": "jpg1", "name": "one.jpg", "cTag": "c1", "file": { "mimeType": "image/jpeg" }, "image": { "width": 4000, "height": 3000 }, "@microsoft.graph.downloadUrl": "https://download.example/jpg1" },
                    { "id": "heic1", "name": "two.HEIC", "cTag": "c2", "file": { "mimeType": "application/octet-stream" }, "@microsoft.graph.downloadUrl": "https://download.example/heic1" },
                    { "id": "raw1", "name": "three.ARW", "cTag": "c3", "file": { "mimeType": "image/tiff" }, "@microsoft.graph.downloadUrl": "https://download.example/raw1" },
                    { "id": "vid1", "name": "nope.mp4", "file": { "mimeType": "video/mp4" }, "@microsoft.graph.downloadUrl": "https://download.example/vid1" }
                  ],
                  "children@odata.nextLink": "\(nextLink)"
                }
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(json.utf8)
                )
            }

            if request.url?.absoluteString == nextLink {
                let json = """
                { "value": [ { "id": "png1", "name": "four.png", "cTag": "c4", "file": { "mimeType": "image/png" }, "@microsoft.graph.downloadUrl": "https://download.example/png1" } ] }
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(json.utf8)
                )
            }

            throw URLError(.badURL)
        }
        defer { MockURLProtocol.removeHandler(for: handlerId) }

        let service = OneDrivePhotosService(authService: TestTokenProvider(), session: session)
        let items = try await service.searchPhotos(inAlbumId: "a1")

        #expect(items.contains(where: { $0.id == "jpg1" }))
        #expect(items.contains(where: { $0.id == "heic1" }))
        #expect(items.contains(where: { $0.id == "png1" }))
        #expect(items.contains(where: { $0.id == "vid1" }) == false)

        if LibRawDecoder.isAvailable() {
            #expect(items.contains(where: { $0.id == "raw1" }))
        } else {
            #expect(items.contains(where: { $0.id == "raw1" }) == false)
        }
    }

    @Test func verifyAlbumExistsReturnsAlbumWhenBundleAlbumFacetPresent() async throws {
        let recorder = RequestRecorder()
        let (session, handlerId) = makeSession { request in
            recorder.record(request)

            let json = """
            { "id": "a1", "name": "Album 1", "webUrl": "https://onedrive.example/a1", "bundle": { "album": {} } }
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        defer { MockURLProtocol.removeHandler(for: handlerId) }

        let service = OneDrivePhotosService(authService: TestTokenProvider(), session: session)
        let album = try await service.verifyAlbumExists(albumId: "a1")
        #expect(album?.id == "a1")
        #expect(album?.name == "Album 1")
        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(recorder.requests.first?.url?.path.hasSuffix("/me/drive/bundles/a1") == true)
    }

    @Test func searchPhotosInAlbumHandlesExpandedChildrenPaging() async throws {
        let recorder = RequestRecorder()
        let nextLink = "https://graph.microsoft.com/v1.0/me/drive/items/a1/children?$skiptoken=abc"
        let (session, handlerId) = makeSession { request in
            recorder.record(request)

            if request.url?.path.hasSuffix("/me/drive/items/a1") == true {
                let json = """
                {
                  "id": "a1",
                  "children": [
                    { "id": "p1", "cTag": "c1", "file": { "mimeType": "image/jpeg" }, "image": { "width": 1920, "height": 1080 }, "@microsoft.graph.downloadUrl": "https://download.example/p1" },
                    { "id": "v1", "file": { "mimeType": "video/mp4" }, "@microsoft.graph.downloadUrl": "https://download.example/v1" }
                  ],
                  "children@odata.nextLink": "\(nextLink)"
                }
                """
                let data = Data(json.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }

            if request.url?.absoluteString == nextLink {
                let json = """
                {
                  "value": [
                    { "id": "p2", "cTag": "c2", "image": { "width": 800, "height": 600 }, "@microsoft.graph.downloadUrl": "https://download.example/p2" }
                  ]
                }
                """
                let data = Data(json.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }

            throw URLError(.badURL)
        }
        defer { MockURLProtocol.removeHandler(for: handlerId) }

        let service = OneDrivePhotosService(authService: TestTokenProvider(), session: session)
        let photos = try await service.searchPhotos(inAlbumId: "a1")
        #expect(photos.map(\.id) == ["p1", "p2"])
        #expect(photos.first?.pixelWidth == 1920)
        #expect(photos.first?.pixelHeight == 1080)
        #expect(recorder.requests.count == 2)
        #expect(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" })
    }

    @Test func listAlbumsFallsBackToUnfilteredWhenFilterReturnsEmpty() async throws {
        let (session, handlerId) = makeSession { request in
            let json: String
            let isFiltered = request.url?.query?.contains("bundle%2Falbum%20ne%20null") == true
                || request.url?.query?.contains("bundle/album%20ne%20null") == true
            if isFiltered {
                json = """
                { "value": [] }
                """
            } else {
                json = """
                {
                  "value": [
                    { "id": "a1", "name": "Album 1", "webUrl": "https://photos.onedrive.com/album/a1" },
                    { "id": "x1", "name": "Not an album", "webUrl": "https://onedrive.example/x1", "bundle": { } }
                  ]
                }
                """
            }
            let data = Data(json.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        defer { MockURLProtocol.removeHandler(for: handlerId) }

        let service = OneDrivePhotosService(authService: TestTokenProvider(), session: session)
        let albums = try await service.listAlbums()
        #expect(albums.map(\.id) == ["a1"])
    }
}
