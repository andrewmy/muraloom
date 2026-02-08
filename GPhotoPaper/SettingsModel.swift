import Foundation
import AppKit // For NSScreen

enum WallpaperChangeFrequency: String, CaseIterable, Identifiable {
    // Stable stored values (UserDefaults)
    case never = "never"
    case hourly = "hourly"
    case sixHours = "six_hours"
    case daily = "daily"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .never: return "Never"
        case .hourly: return "Every Hour"
        case .sixHours: return "Every 6 Hours"
        case .daily: return "Daily"
        }
    }
}

enum WallpaperFillMode: String, CaseIterable, Identifiable {
    // Stable stored values (UserDefaults)
    case fill = "fill"
    case fit = "fit"
    case stretch = "stretch"
    case center = "center"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        case .center: return "Center"
        }
    }
}

class SettingsModel: ObservableObject {
    private let userDefaults: UserDefaults
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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isLoadingFromDisk = true
        self.changeFrequency = userDefaults.string(forKey: "changeFrequency")
            .flatMap(WallpaperChangeFrequency.init(rawValue:))
            ?? .daily
        self.isPaused = userDefaults.bool(forKey: "isPaused")
        self.pickRandomly = userDefaults.bool(forKey: "pickRandomly")
        let initialMinimumPictureWidth = userDefaults.double(forKey: "minimumPictureWidth")
        self.minimumPictureWidth = initialMinimumPictureWidth == 0.0
            ? Self.recommendedMinimumPictureWidthPixels()
            : initialMinimumPictureWidth
        self.horizontalPhotosOnly = userDefaults.bool(forKey: "horizontalPhotosOnly")
        self.wallpaperFillMode = userDefaults.string(forKey: "wallpaperFillMode")
            .flatMap(WallpaperFillMode.init(rawValue:))
            ?? .fill
        self.selectedAlbumId = userDefaults.string(forKey: "selectedAlbumId").flatMap { $0.isEmpty ? nil : $0 }
        self.selectedAlbumName = userDefaults.string(forKey: "selectedAlbumName").flatMap { $0.isEmpty ? nil : $0 }
        self.selectedAlbumWebUrl = userDefaults.string(forKey: "selectedAlbumWebUrl").flatMap { $0.isEmpty ? nil : $0 }.flatMap(URL.init(string:))
        self.lastPickedIndex = userDefaults.integer(forKey: "lastPickedIndex")
        let lastUpdateTimestamp = userDefaults.double(forKey: "lastSuccessfulWallpaperUpdate")
        self.lastSuccessfulWallpaperUpdate = lastUpdateTimestamp > 0 ? Date(timeIntervalSince1970: lastUpdateTimestamp) : nil
        self.lastSetWallpaperItemId = userDefaults.string(forKey: "lastSetWallpaperItemId").flatMap { $0.isEmpty ? nil : $0 }
        self.lastSetWallpaperItemName = userDefaults.string(forKey: "lastSetWallpaperItemName").flatMap { $0.isEmpty ? nil : $0 }
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
        userDefaults.set(changeFrequency.rawValue, forKey: "changeFrequency")
        userDefaults.set(isPaused, forKey: "isPaused")
        userDefaults.set(pickRandomly, forKey: "pickRandomly")
        userDefaults.set(minimumPictureWidth, forKey: "minimumPictureWidth")
        userDefaults.set(horizontalPhotosOnly, forKey: "horizontalPhotosOnly")
        userDefaults.set(wallpaperFillMode.rawValue, forKey: "wallpaperFillMode")
        userDefaults.set(selectedAlbumId, forKey: "selectedAlbumId")
        userDefaults.set(selectedAlbumName, forKey: "selectedAlbumName")
        userDefaults.set(selectedAlbumWebUrl?.absoluteString, forKey: "selectedAlbumWebUrl")
        userDefaults.set(lastPickedIndex, forKey: "lastPickedIndex")
        userDefaults.set(lastSetWallpaperItemId, forKey: "lastSetWallpaperItemId")
        userDefaults.set(lastSetWallpaperItemName, forKey: "lastSetWallpaperItemName")
        if let lastSuccessfulWallpaperUpdate {
            userDefaults.set(lastSuccessfulWallpaperUpdate.timeIntervalSince1970, forKey: "lastSuccessfulWallpaperUpdate")
        } else {
            userDefaults.removeObject(forKey: "lastSuccessfulWallpaperUpdate")
        }
    }

    /// Forces settings to be flushed to disk. Useful right after a wallpaper change so the
    /// current filename/id persist even if the user quits immediately.
    @MainActor
    func flushToDisk() {
        // Ensure all persisted keys are written before syncing.
        saveSettings()
        _ = userDefaults.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }
}
