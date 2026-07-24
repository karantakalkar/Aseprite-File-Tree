# Aseprite File Tree

<img width="746" height="624" alt="Screenshot 2026-07-23 174501" src="https://github.com/user-attachments/assets/a464f117-7102-43cd-99ea-c071b15a51da" />


![Operations](Images/Operations.gif)

A lightweight Aseprite extension that opens a floating file tree browser. It shows nested folders and common art files in a tree view, then opens a clicked file in Aseprite. The browser respects the active Aseprite theme so it blends in with both light and dark skins.

## Install

1. Run `.\build-extension.ps1`.
2. Open Aseprite.
3. Go to `Edit > Preferences > Extensions`.
4. Add `aseprite-file-tree.aseprite-extension`.
5. Restart Aseprite if the command does not appear immediately.

## Verify

Run `.\run-tests.ps1` for filesystem behavior tests, then `.\build-extension.ps1` and `.\verify-extension.ps1` for the packaged extension checks.

## Use

Open `File Tree` from Aseprite's script/plugin menu. The root path defaults to the last saved path, then to Aseprite's user documents folder.
Edit the Path field to navigate automatically after you stop typing.

### Controls

```text
< Back    Return to the previous root folder.
^ Up      Use the parent folder as the root.
Sprite    Use the current sprite's folder as the root.
Root      Navigate to the pinned root folder (set via right-click).
Expand All / Collapse All
          Toggle every folder below the current root.
Preview   Cycle Off, On, and Ref preview modes.
```

The tree checks cached and expanded folders for external filesystem changes once per second.

### Mouse Interactions

- **Single-click** a folder to expand or collapse it.
- **Single-click** a file to select (highlight) it.
- **Double-click** a file to open it in Aseprite.
- **Double-click** a folder to drill into it as the new root.
- **Right-click** a folder to create a new file or folder, cut/copy/paste, set root, add/remove favorite, copy path, or reveal it in the system file manager.
- **Right-click** empty tree space to create a new file or folder in the current root.
- Copy Path and Reveal work on Windows, macOS, and Linux.
- New files ask for a name and file type before they are created.
- **Right-click** a file or folder and choose "Rename" to rename it.
- **Right-click** a file or folder and choose "Cut" or "Copy", then paste it into a folder or empty tree space.
- **Drag** a file or folder onto another folder to move it. Hold **Ctrl** while dragging to copy it.
- Keep the left mouse button held over a collapsed folder for 0.5 seconds to expand it while dragging.
- Drop an item on the Root row or empty tree space to move or copy it into the current root folder.
- Valid drag destinations use a cyan outline and a move cursor; invalid destinations use the blocked cursor.
- File rename autofill hides the extension. Rename preserves it when you omit one and uses a typed extension when you include one.
- **Right-click** a file or folder and choose "Delete" to permanently delete it after confirmation. Folder deletion is recursive.
- Assign Red, Green, Blue, Yellow, or Purple row colors from a file or folder's right-click menu.
- Folder colors cascade to all descendants. A directly tagged child uses its own color instead.
- Color tags are stored locally and follow renamed or moved items.
- Use **Preview** to cycle through **Off**, **On**, and **Ref**.
- **Preview: Off** shows the full file tree.
- **Preview: On** shows the tree and the resizable right-side preview pane. Single-click a file to preview its first frame.
- **Preview: Ref** hides the tree and turns the full canvas into an interactive viewer for the file that was selected in the tree.
- Drag the divider between the tree and preview pane to resize the preview. Hovering the divider switches to Aseprite's horizontal resize cursor.
- In Preview Ref, use the mouse wheel to zoom and middle-mouse drag to pan, matching Aseprite's canvas navigation.
- Guidance is shown in the bottom panel so it never covers the reference image.
- The high-contrast Preview Ref toolbar provides **Fit**, **100%**, zoom out/in, **Pick Primary Color**, **Pick Secondary Color**, and **Crop**.
- **Fit** scales the complete reference into the available image area. **100%** displays one image pixel as one screen pixel.
- The Primary and Secondary color pickers share one toolbar row.
- **Primary** is Aseprite's foreground drawing color. **Secondary** is its alternate/background color.
- Choose a Pick button, then left-click the reference image to sample that color. **Ctrl-click** still picks Primary and **Shift-click** still picks Secondary.
- Search and Type are hidden in Preview On and Preview Ref; Path remains available.
- Single-clicking any file or folder updates Path to that item's full path.
- Entering a folder in Path navigates into it. Entering a supported image-file path navigates to its parent folder, selects the file, and loads it in Preview On or Preview Ref.
- Choose **Crop**, drag a rectangle with the left mouse button, then choose **Copy Crop**. Paste the copied pixels into the active sprite with **Ctrl+V**.
- Aseprite may show its clipboard-write permission prompt the first time **Copy Crop** is used.
- Leaving Preview Ref clears its temporary zoom, pan, crop, and sampled-color state.
- The tree refreshes automatically after creating, renaming, or deleting files and folders.
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
