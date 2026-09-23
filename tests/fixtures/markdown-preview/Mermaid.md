# Diagrams in Markdown

Mermaid diagrams stay inside the preview, alongside normal text and tables.

## Flowchart

```mermaid
flowchart LR
    A[Markdown file] --> B{Preview style}
    B --> C[Solid background]
    B --> D[Liquid Glass]
    C --> E[Read and explore]
    D --> E
```

There should be comfortable spacing before and after this diagram.

## Sequence

```mermaid
sequenceDiagram
    participant Reader
    participant Preview
    Reader->>Preview: Select Markdown
    Preview-->>Reader: Show formatted content
    Reader->>Preview: Resize window
    Preview-->>Reader: Fit the diagram
```

## Table and code

| Feature | Behavior |
| --- | --- |
| Background | Remember your choice |
| Diagrams | Render locally |

```swift
let preview = "Readable Markdown"
if !preview.isEmpty {
    print(preview)
}
```

This paragraph should be clearly separated from the code above.

## Repeated diagrams

```mermaid
flowchart LR
    A --> B
```

```mermaid
flowchart LR
    A --> B
```

Both identical diagrams should appear independently.
