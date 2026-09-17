# Architecture diagrams

- `architecture-diagram.png`: current workflow, 2400 pixels wide.
- `architecture-diagram.svg`: version that stays sharp when resized, with a title
  and description for screen readers.
- `architecture-diagram-v1.png`: original workflow, before local approval was added.

The current diagram shows which steps are automatic and which are manual:
detection, approval on DC-01, resending the same alert, checking AD account state,
and checking Event ID 4725 in Splunk. See [the lab test results](../docs/validation-2026-09-17.md)
for what was tested and the remaining limitations.

To regenerate the current SVG and PNG, install Inkscape and DejaVu Sans fonts,
then run from the repository root:

```bash
python3 scripts/render_architecture.py
```

The renderer uses Python's standard library to create the SVG and Inkscape to
export the PNG. It does not alter the screenshots captured from the lab.
