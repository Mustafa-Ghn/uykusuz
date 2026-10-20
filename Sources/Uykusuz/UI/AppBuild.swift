import Foundation

/// The version this build carries in its Info.plist:
/// `CFBundleShortVersionString` and `CFBundleVersion`. A binary run from
/// `swift run` has no Info.plist, so it has neither.
struct AppBuild: Equatable, Sendable {
    var version: String?
    var build: String?

    static let current = AppBuild(info: Bundle.main.infoDictionary ?? [:])

    init(version: String?, build: String?) {
        self.version = version
        self.build = build
    }

    init(info: [String: Any]) {
        version = Self.nonEmpty(info["CFBundleShortVersionString"])
        build = Self.nonEmpty(info["CFBundleVersion"])
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// For Settings and the launch log: "0.1.0 (1)", or what is missing.
    var label: String {
        switch (version, build) {
        case let (version?, build?): "\(version) (\(build))"
        case let (version?, nil): version
        case (nil, _): "sürüm yok: bu derlemede Info.plist yok"
        }
    }
}
