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
    @Published var changeFrequency: WallpaperChangeFrequency = .daily
    @Published var pickRandomly: Bool = true
    @Published var minimumPictureWidth: Double = Double(NSScreen.main?.frame.width ?? 1920.0)
    @Published var horizontalPhotosOnly: Bool = true
    @Published var wallpaperFillMode: WallpaperFillMode = .fill

    // App-created album ID for persistent storage
    @Published var appCreatedAlbumId: String? = nil
    @Published var appCreatedAlbumName: String? = nil // To display to the user
}