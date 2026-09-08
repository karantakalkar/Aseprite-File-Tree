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
Reveal Sprite
          Expand parent folders, select the active sprite, and scroll to it.
Root      Navigate to the pinned root folder (set via right-click).
Expand All / Collapse All
          Toggle every folder below the current root.
Preview   Cycle Off, On, and Ref preview modes.
```

The tree polls the root every second and checks up to 16 cached folders per tick. Larger trees are checked in rotation.

### Mouse Interactions

- **Single-click** a folder to expand or collapse it.
- **Single-click** a file to select (highlight) it.
- **Double-click** a file to open it in Aseprite.
- Use a folder's **Open** context action to make it the new root. Clicking a folder toggles its expansion.
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
- Search and Type remain available in Preview On and are hidden in Preview Ref; Path remains available.
- Single-clicking any file or folder updates Path to that item's full path.
- Entering a folder in Path navigates into it. Entering a supported image-file path navigates to its parent folder, selects the file, and loads it in Preview On or Preview Ref.
- Choose **Crop**, drag a rectangle with the left mouse button, then choose **Copy Crop**. Paste the copied pixels into the active sprite with **Ctrl+V**.
- Aseprite may show its clipboard-write permission prompt the first time **Copy Crop** is used.
- Leaving Preview Ref clears its temporary zoom, pan, crop, and sampled-color state.
- The tree refreshes automatically after creating, renaming, or deleting files and folders.
- **Right-click** the Root label to clear the pinned root.
- **Mouse wheel** or **scrollbar** to scroll. **Shift + wheel** for horizontal scroll.

### Multiple selection and operations

- **Ctrl-click** adds/removes an item; use **Command-click** on macOS. **Shift-click** selects a visible range. Ctrl/Command+Shift adds a range to the existing selection.
- The selection count includes selected items inside collapsed folders. Changing Search or Type clears the selection.
- Right-clicking a selected item keeps the group. Right-clicking another item selects that item. A plain click selects one item when the mouse is released, so a drag can still move the whole group.
- **Cut**, **Copy**, **Delete**, drag-move, and drag-copy apply to the group. Selected children of a selected folder are processed through their parent once.
- Hold **Ctrl** while dragging to copy; use **Option** on macOS. Every selected item's destination must be valid for the drop to proceed.
- **Paste** transfers the entire clipboard into the chosen folder. Conflict choices can apply to the rest of the batch. Cancelling stops the remaining transfers; completed transfers stay completed, and unprocessed cut items remain on the clipboard.
- **Rename** prompts for each selected item, children before parents. Cancel ends the remaining prompts.
- **Open** opens selected files and expands selected folders. **Copy Path** copies all selected paths on separate lines. **Reveal in File Manager**, color tags, and adding/removing favorites also support groups.
- New File, New Folder, Paste, and Set Root use one destination. Their folder context actions appear for a single selected folder; empty-space Paste targets the current root.
- With the tree focused, **Ctrl/Command+A**, **C**, **X**, and **V** select all, copy, cut, and paste. **Delete** opens group deletion confirmation, **F2** starts rename, **Enter** opens, and **Escape** clears selection.

### Reveal and reference navigation

**Reveal Sprite** keeps the current root when it contains the active sprite, clears hiding filters, expands its ancestors, and selects and scrolls to it. For a sprite outside the root, it uses that sprite's parent folder. The sprite must already be saved. In Ref mode, reveal returns to the tree-and-preview layout.

In **Preview Ref**, **< Prev** and **Next >** switch between supported image files in the current reference's folder, in the same folders-first, case-insensitive filename order as the tree. Navigation stops at the first/last file. Switching files resets the reference camera and crop; refreshing the same file preserves the camera.

### Toggle shortcut

Go to **Edit → Keyboard Shortcuts**, search for **File Tree**, and assign a key to toggle the browser open/closed.

### Search & Filter

- **Search** field filters files and folders by plain substring (250 ms debounce).
- **Type** dropdown filters by file extension (.png, .ase, etc).
- When a type filter is active, only files matching the type appear; folders show only as ancestors of matching files.
- Both text search and type-only filtering search nested folders. Index construction yields between small batches; cached lowercase names and parent links avoid repeatedly copying ancestor lists.
- Search is limited to 128 folder levels to bound traversal through deeply nested folders or directory-link cycles. A depth-limit message appears when this limit is reached. Folder enumeration itself is synchronous, so a single very large or slow network directory can still delay a tick.

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

- Preview content is checked in 256 KiB chunks to catch saves whose file size did not change. Large references take several ticks to finish checking. Other files use folder name/type checks, so ordinary saves do not restart search indexing; this is polling, not a native operating-system event watcher.
- Windows shell integration uses encoded PowerShell commands and literal paths, including Unicode and characters such as `%` and `&`. Older Aseprite builds that disable Lua file removal/rename use platform fallbacks; permission-denial errors are reported rather than retried through a fallback.
- macOS uses Command for selection/shortcuts and Option for copy-drag. Finder reveal uses `open -R`; Linux opens the containing folder with `xdg-open`.
- Search folds ASCII case using Lua's lowercase operation; full Unicode case folding and filesystem link-identity detection are not available in this implementation.
- The automated tests include real Windows file operations on Aseprite 1.3.7 and simulated macOS/Linux behavior. Native macOS/Linux and visual UI verification still require those environments.

This is a floating dialog because the public Aseprite extension API does not expose native docked editor tabs.
