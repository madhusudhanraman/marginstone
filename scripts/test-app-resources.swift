import Foundation
extension Bundle { static var module: Bundle { fatalError("Development resource fallback was used") } }
@main struct Check {
 static func main() {
  let bundle = AppResources.bundle
  precondition(bundle.bundleURL.path.hasPrefix(Bundle.main.bundleURL.path + "/Contents/Resources/"))
  for name in ["nautilus", "leaf", "ammonite", "brachiopod", "fern", "band-0"] {
   precondition(bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources") != nil)
  }
  precondition(bundle.url(forResource: "repository", withExtension: "sh", subdirectory: "Resources") != nil)
  print("PASS: packaged app resources resolve without development fallback")
 }
}
