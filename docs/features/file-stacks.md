# File Stacks

File Stacks are persistent Nodebay objects with stable identifiers, names, ordered members, and saved bookmarks. A stack can be created by dropping one tile onto another or from selected files, then expanded, reordered, previewed, renamed, dissolved, or edited without changing disk originals.

Dragging a collapsed stack creates one AppKit drag session containing separate underlying file URLs. Finder receives individual files, not a ZIP or synthetic folder. Batch Markdown conversion preserves partial successes and creates a separate result stack. Batch image compression likewise works from safe copies.
