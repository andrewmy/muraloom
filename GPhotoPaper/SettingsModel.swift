import Foundation
import AppKit // For NSScreen

enum WallpaperChangeFrequency: String, CaseIterable, Identifiable {
    case never = "Never"
    case hourly = "Every Hour"
    case sixHours = "Every 6 Hours"
    case daily = "Daily"

    var id: String { self.rawValue }
}

enum WallpaperFillMode: String, CaseIterable, Identifiable {
    case fill = "Fill"
    case fit = "Fit"
    case stretch = "Stretch"
    case center = "Center"

    var id: String { self.rawValue }
}

class SettingsModel: ObservableObject {
    private var isLoadingFromDisk: Bool = true

    @Published var changeFrequency: WallpaperChangeFrequency { didSet { persistIfReady() } }
    @Published var isPaused: Bool { didSet { persistIfReady() } }
    @Published var pickRandomly: Bool { didSet { persistIfReady() } }
    @Published var minimumPictureWidth: Double { didSet { persistIfReady() } }
    @Published var horizontalPhotosOnly: Bool { didSet { persistIfReady() } }
    @Published var wallpaperFillMode: WallpaperFillMode { didSet { persistIfReady() } }

    // OneDrive album selection (persisted)
    @Published var selectedAlbumId: String? { didSet { persistIfReady() } }
    @Published var selectedAlbumName: String? { didSet { persistIfReady() } }
    @Published var selectedAlbumWebUrl: URL? { didSet { persistIfReady() } }
    @Published var lastPickedIndex: Int { didSet { persistIfReady() } }
    @Published var lastSuccessfulWallpaperUpdate: Date? { didSet { persistIfReady() } }
    @Published var lastSetWallpaperItemId: String? { didSet { persistIfReady() } }
    @Published var lastSetWallpaperItemName: String? { didSet { persistIfReady() } }
    @Published var albumPictureCount: Int = 0
    @Published var showNoPicturesWarning: Bool = false

    init() {
        isLoadingFromDisk = true
        self.changeFrequency = UserDefaults.standard.string(forKey: "changeFrequency").flatMap(WallpaperChangeFrequency.init(rawValue:)) ?? .daily
        self.isPaused = UserDefaults.standard.bool(forKey: "isPaused")
        self.pickRandomly = UserDefaults.standard.bool(forKey: "pickRandomly")
        let initialMinimumPictureWidth = UserDefaults.standard.double(forKey: "minimumPictureWidth")
        self.minimumPictureWidth = initialMinimumPictureWidth == 0.0
            ? Self.recommendedMinimumPictureWidthPixels()
            : initialMinimumPictureWidth
        self.horizontalPhotosOnly = UserDefaults.standard.bool(forKey: "horizontalPhotosOnly")
        self.wallpaperFillMode = UserDefaults.standard.string(forKey: "wallpaperFillMode").flatMap(WallpaperFillMode.init(rawValue:)) ?? .fill
        self.selectedAlbumId = UserDefaults.standard.string(forKey: "selectedAlbumId").flatMap { $0.isEmpty ? nil : $0 }
        self.selectedAlbumName = UserDefaults.standard.string(forKey: "selectedAlbumName").flatMap { $0.isEmpty ? nil : $0 }
        self.selectedAlbumWebUrl = UserDefaults.standard.string(forKey: "selectedAlbumWebUrl").flatMap { $0.isEmpty ? nil : $0 }.flatMap(URL.init(string:))
        self.lastPickedIndex = UserDefaults.standard.integer(forKey: "lastPickedIndex")
        let lastUpdateTimestamp = UserDefaults.standard.double(forKey: "lastSuccessfulWallpaperUpdate")
        self.lastSuccessfulWallpaperUpdate = lastUpdateTimestamp > 0 ? Date(timeIntervalSince1970: lastUpdateTimestamp) : nil
        self.lastSetWallpaperItemId = UserDefaults.standard.string(forKey: "lastSetWallpaperItemId").flatMap { $0.isEmpty ? nil : $0 }
        self.lastSetWallpaperItemName = UserDefaults.standard.string(forKey: "lastSetWallpaperItemName").flatMap { $0.isEmpty ? nil : $0 }
        isLoadingFromDisk = false
    }

    private static func recommendedMinimumPictureWidthPixels() -> Double {
        Double(WallpaperImageTranscoder.maxRecommendedDisplayPixelWidth())
    }

    private func persistIfReady() {
        if isLoadingFromDisk { return }
        saveSettings()
    }

    private func saveSettings() {
        UserDefaults.standard.set(changeFrequency.rawValue, forKey: "changeFrequency")
        UserDefaults.standard.set(isPaused, forKey: "isPaused")
        UserDefaults.standard.set(pickRandomly, forKey: "pickRandomly")
        UserDefaults.standard.set(minimumPictureWidth, forKey: "minimumPictureWidth")
        UserDefaults.standard.set(horizontalPhotosOnly, forKey: "horizontalPhotosOnly")
        UserDefaults.standard.set(wallpaperFillMode.rawValue, forKey: "wallpaperFillMode")
        UserDefaults.standard.set(selectedAlbumId, forKey: "selectedAlbumId")
        UserDefaults.standard.set(selectedAlbumName, forKey: "selectedAlbumName")
        UserDefaults.standard.set(selectedAlbumWebUrl?.absoluteString, forKey: "selectedAlbumWebUrl")
        UserDefaults.standard.set(lastPickedIndex, forKey: "lastPickedIndex")
        UserDefaults.standard.set(lastSetWallpaperItemId, forKey: "lastSetWallpaperItemId")
        UserDefaults.standard.set(lastSetWallpaperItemName, forKey: "lastSetWallpaperItemName")
        if let lastSuccessfulWallpaperUpdate {
            UserDefaults.standard.set(lastSuccessfulWallpaperUpdate.timeIntervalSince1970, forKey: "lastSuccessfulWallpaperUpdate")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastSuccessfulWallpaperUpdate")
        }
    }

    /// Forces settings to be flushed to disk. Useful right after a wallpaper change so the
    /// current filename/id persist even if the user quits immediately.
    @MainActor
    func flushToDisk() {
        // Ensure all persisted keys are written before syncing.
        saveSettings()
        _ = UserDefaults.standard.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }
}
