# Architecture diagrams

- `architecture-diagram.png`: current approval flow, rendered at 2400 pixels wide.
- `architecture-diagram.svg`: scalable version with accessible title and description.
- `architecture-diagram-v1.png`: archived original diagram; direct response without
  the new local approval step.

The current diagram distinguishes automatic detection, local operator approval,
manual resubmission, AD readback, and a separate manual Event 4725 audit in Splunk.
See [the validation record](../docs/validation-2026-09-17.md) for evidence and the
limits of the live test.

To regenerate the current SVG and PNG, install Inkscape and DejaVu Sans fonts,
then run from the repository root:

```bash
python3 scripts/render_architecture.py
```

The renderer uses Python's standard library to create the SVG and Inkscape to
export the PNG. It does not alter the screenshots captured from the lab.
