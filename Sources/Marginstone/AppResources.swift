import Foundation

// SwiftPM's generated accessor looks beside the .app before falling back to
// the original build directory. Installed apps must never use that fallback.
enum AppResources {
    static let bundle: Bundle = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resources = Bundle.main.resourceURL,
                  let bundle = Bundle(url: resources.appendingPathComponent("Marginstone_Marginstone.bundle")) else {
                fatalError("Marginstone’s packaged resources are missing. Reinstall the app.")
            }
            return bundle
        }
        return Bundle.module
    }()
}
