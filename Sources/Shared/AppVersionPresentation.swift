import Foundation

struct AppVersionPresentation: Equatable {
    let shortVersion: String
    let buildVersion: String

    init(
        shortVersion: String?,
        buildVersion: String?
    ) {
        self.shortVersion = Self.normalized(shortVersion)
        self.buildVersion = Self.normalized(buildVersion)
    }

    init(bundle: Bundle = .main) {
        self.init(
            shortVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            buildVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String
        )
    }

    var versionAndBuild: String {
        "\(shortVersion) (\(buildVersion))"
    }

    func hybridAppText(activeEditionName: String) -> String {
        "Windsify \(versionAndBuild) · \(activeEditionName)"
    }

    var freeAppText: String {
        "Windsify Free \(versionAndBuild)"
    }

    private static func normalized(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let normalized, !normalized.isEmpty else {
            return "Unknown"
        }
        return normalized
    }
}
