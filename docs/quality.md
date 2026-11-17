# Static gates and tooling

The source-only gates that run outside the game project. The behavioural suites are `docs/tests.md`;
the commands are `WORKFLOW.md`.

## Formatting

Formatting. No formatter is run. gdformat is intentionally not adopted: it is configurable only by
line length and indentation, and it conflicts with the adopted style of the repo — two blank lines
around every function, trailing commas, parenthesized method chains. This unifies the style with
the widely accepted conventions, but doesn't meaningfully improve quality or readability, and in
some cases worsens it. Additionally, it is written in pure Python and slow. Keep the current layout
by review; do not add a formatter gate.

## Linting

`gdlint` 4.5.0 lints the shipped `.gd` files only. Tests and tools are excluded because
gdtoolkit's parser rejects some valid test syntax. The config is `.gdlintrc`.

The structural rules are disabled because they conflict with the service layout: the repo
interleaves public and private state by subsystem, a correct boundary beats a line count, the
facades intentionally expose many methods, and the act code uses guard clauses. The remaining
rules catch naming drift, unused arguments, duplicate loads, self-comparisons, unassigned
expressions and whitespace.

Install the pinned toolchain with `python3 -m pip install -r scripts/requirements-lint.txt`, then
run `scripts/lint.sh`. The source-checks CI job runs the same command and blocks the build on a
finding. The tree is clean; a new finding fails. Pin gdtoolkit 4.5.0; bump it deliberately with a
Godot upgrade and re-run the gate.

## Complexity

Complexity. gdradon cc is not used. It converts GDScript to Python and cannot parse some of the
valid GDScript code, discards every expression so and/or are not counted, has no threshold or JSON
options, and exits 0 on failure. Use a parser-based baseline ratchet if complexity gating is
wanted.

## Related docs

- `docs/tests.md` — the behavioural suites and the runner.
- `WORKFLOW.md` — the commands and the commit flow.
