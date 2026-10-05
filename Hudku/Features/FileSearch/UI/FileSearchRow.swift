import SwiftUI

/// An `@word` match in the launcher, drawn with its own file thumbnail.
struct FileSearchRow: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    let selected: Bool
    @State private var image: NSImage?
    @State private var hovered = false

    init(result: FileSearchResult, selected: Bool) {
        self.result = result
        self.selected = selected
        _image = State(initialValue: IconCache.cachedFitted(forFile: result.id))
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// A folder is named by where it sits: half the hits are some `src` or `Hudku`.
    private var label: Text {
        guard result.isDirectory, !result.parentName.isEmpty else { return Text(result.name) }
        let parent = Text("\(result.parentName)/").foregroundStyle(.secondary)
        return Text("\(parent)\(result.name)")
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let image {
                    Image(nsImage: image).resizable()
                } else {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.iconPlaceholder)
                }
            }
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            // The column is too narrow for a path beside the name; the actions menu states it.
            label
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.name)
        .accessibilityValue(result.parentPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: IconRequest(result.id)) {
            if let warm = IconCache.cachedFitted(forFile: result.id) {
                image = warm
                return
            }
            image = await IconCache.loadFittedAsync(forFile: result.id)
        }
    }
}

/// The actions an inline file row's menu offers; each hands the result to the coordinator.
@MainActor
enum FileSearchActionsMenu {
    static func content(
        result: FileSearchResult, core: AppCore, target: PasteTarget?
    ) -> PopoverMenuContent {
        let coordinator = core.fileSearchCoordinator
        return PopoverMenuContent(
            header: result.name,
            items: [
                PopoverMenuItem(
                    title: result.isDirectory ? "Open Folder" : "Open File",
                    systemImage: result.isDirectory ? "folder" : "doc", shortcut: "↵"
                ) { coordinator.open(result) },
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵"
                ) { coordinator.showInFinder(result) },
                PopoverMenuItem(title: "Share…", systemImage: "square.and.arrow.up") {
                    coordinator.share(result)
                },
                PopoverMenuItem(
                    title: "Copy File", systemImage: "doc.on.clipboard", startsSection: true,
                    shortcut: "⇧⌘C"
                ) { coordinator.copyFile(result) },
                PopoverMenuItem(
                    title: target.map { "Paste File to \($0.name)" } ?? "Paste File",
                    icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "⇧⌘V"
                ) { coordinator.pasteFile(result) },
                PopoverMenuItem(
                    title: "Copy Name", systemImage: "doc.on.clipboard", shortcut: "⌥⌘C"
                ) { coordinator.copyName(result) },
                PopoverMenuItem(
                    title: "Copy Path", systemImage: "doc.on.clipboard", shortcut: "⌃⌘C"
                ) { coordinator.copyPath(result) },
                PopoverMenuItem(
                    title: "Move to Trash", systemImage: "trash", startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) { coordinator.trash(result) }
            ])
    }
}
