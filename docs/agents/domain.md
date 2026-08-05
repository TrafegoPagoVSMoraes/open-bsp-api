# Domain documentation

This repository uses a multi-context layout.

Before changing code, read `CONTEXT-MAP.md`, then the `CONTEXT.md` files for the
contexts affected by the task. Read applicable system-wide decisions in
`docs/adr/` as well.

## Layout

```text
/
├── CONTEXT-MAP.md
├── docs/adr/
└── docs/contexts/
    ├── messaging/CONTEXT.md
    ├── tracking/CONTEXT.md
    └── plugin/CONTEXT.md
```

The ADR directory contains decisions that affect the system as a whole. If a
future decision belongs to only one context, place it next to that context and
add the location to `CONTEXT-MAP.md`.

Use the vocabulary defined by the relevant context. If a proposed change
contradicts an ADR, surface the conflict explicitly rather than silently
overriding the decision.
