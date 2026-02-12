import Foundation

extension SettingsManager {

    // MARK: - Save Path

    /// Directory path where recordings are saved
    var savePath: URL {
        get {
            // 1. Return active URL if already accessed
            if let secureURL = securityScopedURL {
                return secureURL
            }

            // 2. Try to resolve Custom Path from Bookmark
            if let bookmarkData = defaults.data(forKey: Keys.savePathBookmark) {
                var isStale = false
                do {
                    let url = try URL(resolvingBookmarkData: bookmarkData,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale)

                    if isStale {
                        saveBookmark(for: url)
                    }

                    if url.startAccessingSecurityScopedResource() {
                        securityScopedURL = url
                        return url
                    }
                } catch {
                    LoggerService.shared.log(category: .general, level: .error, message: "Failed to resolve bookmark: \(error)")
                }
            }

            // 3. Fallback to Sandbox Documents (Default)
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        set {
            // Validate path before accepting it
            do {
                try PathValidator.validatePathString(newValue.path)

                // For external paths, also validate they're within a reasonable directory
                if !newValue.path.hasPrefix(PathManager.shared.rootDataURL.path) {
                    // Additional validation for external paths could go here
                    LoggerService.shared.log(category: .general, level: .info, message: "[Settings] External path selected: \(newValue.path)")
                }
            } catch {
                LoggerService.shared.log(category: .general, level: .error, message: "[Settings] Path validation failed: \(error.localizedDescription)")
                // Reject the invalid path by not updating
                return
            }

            // Stop accessing old resource
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil

            // Create and save bookmark coverage for new path
            saveBookmark(for: newValue)

            // Start accessing new resource (if applicable)
            if newValue.startAccessingSecurityScopedResource() {
                securityScopedURL = newValue
            }

            defaults.set(newValue.path, forKey: Keys.savePath)
            objectWillChange.send()
        }
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            defaults.set(data, forKey: Keys.savePathBookmark)
        } catch {
            LoggerService.shared.log(category: .general, level: .error, message: "Failed to create bookmark: \(error)")
        }
    }
}
