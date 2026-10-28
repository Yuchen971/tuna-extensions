import Foundation
import TunaKit

@objc(CardinalExtension)
public final class CardinalExtension: Extension {
  public override var declaration: ExtensionDeclaration? {
    ExtensionDeclaration(
      metadata: ExtensionMetadata(
        displayName: "Cardinal",
        author: "Yuchen Li",
        description: "Search every file on this Mac with Cardinal.",
        iconName: "magnifyingglass"
      ),
      compatibility: ExtensionDeclarationCompatibility(minTuna: "0.96", minTunaKit: "1.22.0"),
      catalogs: [
        // Catalog and item ids end up in preferences, hotkeys and tuna:// links: never rename them.
        CatalogDeclaration(
          id: "cardinal",
          type: CardinalCatalog.self,
          name: "Cardinal",
          presentation: .liveSearch,
          description: "Search every file on this Mac · Needs the Cardinal app running",
          enabledByDefault: true
        )
      ]
    )
  }
}

/// One entry, "Search Files", that searches as the user types inside it.
public final class CardinalCatalog: Catalog {
  public let identifier: String
  public let name: String

  private let rootItem = CardinalSearchEntry()

  public var objects: [CatalogItem] { [rootItem] }

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
  }

  public func scan() async {
    reportScanFinished()
  }
}

/// The entry users find in global search and step into with →. Named after the task
/// ("Search Files") rather than the app, with "Cardinal" kept as an extra search key.
final class CardinalSearchEntry: CatalogEntity, CatalogHierarchyNode, ScopedCatalogSearchProviding,
  @unchecked Sendable
{
  private static let icon = BrowseCatalogItem.CatalogIcon(symbolName: "magnifyingglass", color: .red)

  init() {
    // The id ends up in preferences, hotkeys and tuna:// links: never rename it.
    super.init(id: "cardinal.search", title: "Search Files", path: nil)
    typeID = .dynamicSearchCatalogEntry
  }

  override var detail: String? { "Every file on this Mac · Cardinal" }

  override var searchKeys: [String] { ["Search Files", "Find Files", "Cardinal"] }

  // Cardinal answers most searches in well under 100 ms, so keep the pause short.
  var scopedSearchConfiguration: ScopedSearchConfiguration {
    ScopedSearchConfiguration(debounce: .milliseconds(120), searchOnChange: true)
  }

  func scopedSearch(query: String) async throws -> [CatalogItem] {
    try await CardinalSearch.items(for: query)
  }

  func hierarchyChildren() -> [CatalogItem] {
    [CardinalMessages.hint()]
  }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .catalogIcon(symbolName: Self.icon.symbolName, color: Self.icon.color, maxDimension: maxDimension)
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    preview(maxDimension: maxDimension)
  }
}
