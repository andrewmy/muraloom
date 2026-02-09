import Foundation

final class AppTesting: ObservableObject {
    let isUITesting: Bool

    init(isUITesting: Bool) {
        self.isUITesting = isUITesting
    }
}

