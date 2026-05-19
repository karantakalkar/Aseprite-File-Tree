
| Light Theme | Dark Theme |
|:-:|:-:|
| ![Light](Sample%20Light.png) | ![Dark](Sample%20Black.png) |

# Aseprite File Tree

A lightweight Aseprite extension that opens a floating file tree browser. It shows nested folders and common art files in a tree view, then opens a clicked file in Aseprite. The browser respects the active Aseprite theme so it blends in with both light and dark skins.

## Install

1. Run `.\build-extension.ps1`.
2. Open Aseprite.
3. Go to `Edit > Preferences > Extensions`.
4. Add `aseprite-file-tree.aseprite-extension`.
5. Restart Aseprite if the command does not appear immediately.

## Use

Open `File Tree` from Aseprite's script/plugin menu. The root path defaults to the last saved path, then to Aseprite's user documents folder.

### Controls

```text
< Back    Return to the previous root folder.
^ Up      Use the parent folder as the root.
Sprite    Use the current sprite's folder as the root.
Root      Navigate to the pinned root folder (set via right-click).
Rescan    Reload folder contents.
```

### Mouse Interactions

- **Single-click** a folder to expand or collapse it.
- **Single-click** a file to select (highlight) it.
- **Double-click** a file to open it in Aseprite.
- **Double-click** a folder to drill into it as the new root.
- **Right-click** a folder for context menu (Set Root, Add/Remove Favorite, Copy Path, Reveal in Explorer).
- **Right-click** the Root label to clear the pinned root.
- **Mouse wheel** or **scrollbar** to scroll. **Shift + wheel** for horizontal scroll.

### Keyboard Shortcut

Go to **Edit → Keyboard Shortcuts**, search for **File Tree**, and assign a key to toggle the browser open/closed.

### Search & Filter

- **Search** field filters files and folders by name (debounced 1.5s).
- **Type** dropdown filters by file extension (.png, .ase, etc).
- When a type filter is active, only files matching the type appear; folders show only as ancestors of matching files.

### Favorites

- Right-click a folder and choose "Add Favorite" to pin it.
- Favorites appear in a panel at the top of the tree.
- Double-click a favorite to navigate to it.
- Right-click a favorite to remove it.

### Supported Files

```text
.ase, .aseprite, .png, .jpg, .jpeg, .gif, .webp, .bmp
```

## Notes

This is a floating dialog because the public Aseprite extension API does not expose native docked editor tabs.
