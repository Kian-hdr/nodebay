# File shelf

The shelf stores persistent references and security-scoped bookmarks, not copies of source files. Files can be dragged in and out, selected with keyboard navigation, previewed with Space, or opened through native context menus. The remove control deletes only the Nodebay reference and offers a dismissible, expiring Undo notice.

Generated conversion, compression, and download outputs are added as ordinary draggable shelf items. Collision-safe naming prevents overwrites. If the disk file is moved externally and its bookmark cannot be resolved, Nodebay reports the missing reference rather than deleting anything.
