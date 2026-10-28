import Foundation
import TunaKit

@objc(KeepAwakeExtension)
public final class KeepAwakeExtension: Extension {
  public override var declaration: ExtensionDeclaration? {
    ExtensionDeclaration(
      metadata: ExtensionMetadata(
        displayName: "Keep Awake",
        author: "Yuchen Li",
        description: "Keep this Mac awake for a while.",
        iconName: "cup.and.saucer"
      ),
      compatibility: ExtensionDeclarationCompatibility(minTuna: "0.96", minTunaKit: "1.22.0"),
      catalogs: [
        // Catalog and item ids end up in preferences, hotkeys and tuna:// links: never rename them.
        CatalogDeclaration(
          id: "keepawake",
          type: KeepAwakeCatalog.self,
          name: "Keep Awake",
          presentation: .liveSearch,
          description: "Keep this Mac awake for a while",
          enabledByDefault: true,
          settings: [KeepAwakeSettings.screen]
        )
      ]
    )
  }
}

enum KeepAwakeSettings {
  static let screen = CatalogSettingDefinition(
    key: "screen",
    type: .string,
    label: "Screen",
    defaultValue: ScreenMode.stayOn.rawValue,
    description: "The Mac stays awake either way.",
    options: [
      .init(value: ScreenMode.stayOn.rawValue, label: "Keep screen on"),
      .init(value: ScreenMode.canTurnOff.rawValue, label: "Let screen turn off"),
    ]
  )

  static func screenMode(in store: CatalogSettingStore) -> ScreenMode {
    ScreenMode(rawValue: store.stringValue(for: screen)) ?? .stayOn
  }
}

/// One entry, "Keep Awake", whose subtitle is the current status.
public final class KeepAwakeCatalog: Catalog {
  public let identifier: String
  public let name: String

  private let rootItem: KeepAwakeEntry

  public var objects: [CatalogItem] { [rootItem] }

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
    rootItem = KeepAwakeEntry(settings: CatalogSettingStore(catalogIdentifier: definition.identifier))
  }

  public func scan() async {
    reportScanFinished()
  }
}

/// The entry users find in global search and step into with → to pick how long.
final class KeepAwakeEntry: CatalogEntity, CatalogHierarchyNode, ScopedCatalogSearchProviding,
  @unchecked Sendable
{
  private let keepAwake: KeepAwake
  private let settings: CatalogSettingStore

  init(keepAwake: KeepAwake = .live, settings: CatalogSettingStore) {
    self.keepAwake = keepAwake
    self.settings = settings
    // The id ends up in preferences, hotkeys and tuna:// links: never rename it.
    super.init(id: "keepawake.entry", title: "Keep Awake", path: nil)
    typeID = .dynamicSearchCatalogEntry
  }

  // Read on every display, so the status is current whenever Tuna shows the entry.
  override var detail: String? { KeepAwakeText.status(keepAwake.current(), now: Date()) }

  override var searchKeys: [String] {
    ["Keep Awake", "Stay Awake", "Caffeinate", "Prevent Sleep", "No Sleep"]
  }

  var scopedSearchConfiguration: ScopedSearchConfiguration {
    ScopedSearchConfiguration(debounce: .milliseconds(60), searchOnChange: true)
  }

  func scopedSearch(query: String) async throws -> [CatalogItem] {
    menu().items(for: query)
  }

  func hierarchyChildren() -> [CatalogItem] {
    menu().items(for: "")
  }

  private func menu() -> KeepAwakeMenu {
    KeepAwakeMenu(
      keepAwake: keepAwake, screen: KeepAwakeSettings.screenMode(in: settings), now: Date())
  }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .catalogIcon(symbolName: "cup.and.saucer.fill", color: .brown, maxDimension: maxDimension)
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    preview(maxDimension: maxDimension)
  }
}
