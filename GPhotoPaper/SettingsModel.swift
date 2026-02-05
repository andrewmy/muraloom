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
    @Published var changeFrequency: WallpaperChangeFrequency { didSet { saveSettings() } }
    @Published var pickRandomly: Bool { didSet { saveSettings() } }
    @Published var minimumPictureWidth: Double { didSet { saveSettings() } }
    @Published var horizontalPhotosOnly: Bool { didSet { saveSettings() } }
    @Published var wallpaperFillMode: WallpaperFillMode { didSet { saveSettings() } }

    // OneDrive album selection (persisted)
    @Published var selectedAlbumId: String? { didSet { saveSettings() } }
    @Published var selectedAlbumName: String? { didSet { saveSettings() } }
    @Published var selectedAlbumWebUrl: URL? { didSet { saveSettings() } }
    @Published var lastPickedIndex: Int { didSet { saveSettings() } }
    @Published var albumPictureCount: Int = 0
    @Published var showNoPicturesWarning: Bool = false

    init() {
        self.changeFrequency = UserDefaults.standard.string(forKey: "changeFrequency").flatMap(WallpaperChangeFrequency.init(rawValue:)) ?? .daily
        self.pickRandomly = UserDefaults.standard.bool(forKey: "pickRandomly")
        let initialMinimumPictureWidth = UserDefaults.standard.double(forKey: "minimumPictureWidth")
        self.minimumPictureWidth = initialMinimumPictureWidth == 0.0 ? Double(NSScreen.main?.frame.width ?? 1920.0) : initialMinimumPictureWidth
        self.horizontalPhotosOnly = UserDefaults.standard.bool(forKey: "horizontalPhotosOnly")
        self.wallpaperFillMode = UserDefaults.standard.string(forKey: "wallpaperFillMode").flatMap(WallpaperFillMode.init(rawValue:)) ?? .fill
        self.selectedAlbumId = UserDefaults.standard.string(forKey: "selectedAlbumId")
        self.selectedAlbumName = UserDefaults.standard.string(forKey: "selectedAlbumName")
        self.selectedAlbumWebUrl = UserDefaults.standard.string(forKey: "selectedAlbumWebUrl").flatMap(URL.init(string:))
        self.lastPickedIndex = UserDefaults.standard.integer(forKey: "lastPickedIndex")
    }

    private func saveSettings() {
        UserDefaults.standard.set(changeFrequency.rawValue, forKey: "changeFrequency")
        UserDefaults.standard.set(pickRandomly, forKey: "pickRandomly")
        UserDefaults.standard.set(minimumPictureWidth, forKey: "minimumPictureWidth")
        UserDefaults.standard.set(horizontalPhotosOnly, forKey: "horizontalPhotosOnly")
        UserDefaults.standard.set(wallpaperFillMode.rawValue, forKey: "wallpaperFillMode")
        UserDefaults.standard.set(selectedAlbumId, forKey: "selectedAlbumId")
        UserDefaults.standard.set(selectedAlbumName, forKey: "selectedAlbumName")
        UserDefaults.standard.set(selectedAlbumWebUrl?.absoluteString, forKey: "selectedAlbumWebUrl")
        UserDefaults.standard.set(lastPickedIndex, forKey: "lastPickedIndex")
    }
}
