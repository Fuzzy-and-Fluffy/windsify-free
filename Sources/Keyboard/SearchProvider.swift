import Combine
import Foundation
import SwiftUI

enum SearchProvider: String, CaseIterable, Identifiable {
    case spotlight
    case raycast

    var id: String { rawValue }
    var name: String { self == .spotlight ? "Spotlight" : "Raycast" }

    static func resolve(_ stored: String?) -> SearchProvider {
        stored.flatMap(Self.init(rawValue:)) ?? .spotlight
    }
}

/// Shared by the full app and standalone Free settings. Test policy uses
/// injected storage, never standard defaults.
final class SearchProviderStore: ObservableObject {
    static let preferenceKey = "searchProvider"
    static let shared = SearchProviderStore()
    @Published private(set) var selection: SearchProvider
    private let write: (String) -> Void

    init(read: () -> String?, write: @escaping (String) -> Void) {
        selection = SearchProvider.resolve(read())
        self.write = write
    }

    convenience init() {
        self.init(read: {
            guard !InputRuntimeSafety.isTestHost else { return nil }
            return UserDefaults.standard.string(forKey: Self.preferenceKey)
        }, write: {
            guard !InputRuntimeSafety.isTestHost else { return }
            UserDefaults.standard.set($0, forKey: Self.preferenceKey)
        })
    }

    func select(_ provider: SearchProvider) {
        selection = provider
        write(provider.rawValue)
    }
}

struct SearchProviderPicker: View {
    @ObservedObject private var store = SearchProviderStore.shared

    var body: some View {
        Picker(L10n.text("Windows key search"), selection: Binding(
            get: { store.selection }, set: { store.select($0) }
        )) {
            ForEach(SearchProvider.allCases) { provider in
                Text(provider.name).tag(provider)
            }
        }
        Text(L10n.text("The Windows key opens your selected search app. Pro Win+S uses the same choice. Spotlight is the default. Raycast must be installed. Existing system and Raycast shortcuts stay unchanged."))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
