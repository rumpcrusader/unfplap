# Static gates and tooling

The gates that need no running game. The behavioural suites are `docs/tests.md`; the commands are
`WORKFLOW.md`.

## Parse check

The parse gate (`scripts/check.sh`) loads every `.gd` file — tests and tools included — in one
headless engine boot and reports the files that do not load. A run without the tool's parsed line
is a failure. The default run also runs the static gate; `--parse` loads only the changed and
untracked scripts, and `--static` runs the gate without Godot or the fetched assets. The cost is
that boot plus each script's preload closure once, so it must never return to one boot per file.

The parse needs the full game project beside the mod, because preloads resolve against its paths. CI
has no game checkout, so the build job gates on the static gate and the lint.

## Formatting

No formatter runs. gdformat is deliberately not adopted: it is configurable only by line length
and indentation and conflicts with the repo's style — two blank lines around every function,
trailing commas, parenthesized method chains. It would standardize the layout without improving
readability, sometimes worsen it, and it is pure Python and slow. Keep the layout by review.

## Linting

gdlint lints the shipped scripts and the test suites through a root configuration and a test one,
the latter adding the test-syntax disables; tools stay excluded. The structural rules are disabled
because they conflict with the service layout: public and private state are interleaved by
subsystem, a correct boundary beats a line count, the facades expose many methods and the act code
uses guard clauses. The remaining rules catch naming drift, unused arguments, duplicate loads,
self-comparisons, unassigned expressions and whitespace.

Install the pinned toolchain and run `scripts/lint.sh`; the source-checks CI job runs the same
command and blocks the build on a finding. Pin the toolkit and bump it with a Godot upgrade.

## Comments

Comments carry what the code cannot: rationale, traps, ordering constraints and game quirks, with no
size cap. The comment checker runs inside the lint gate and in the source-checks CI job. Its rules:

- **R4, private names.** No backticked private member, Godot engine virtuals excepted.
- **R5, doc pointers.** Every backticked doc pointer names a doc that exists; heading anchors are
  not resolved, so a heading rename never edits a comment.
- **R6, copied prose.** A comment sentence may not copy a sentence from a doc.

`--audit` prints the findings as JSON and `--self-test` runs the fixtures. The gate checks
rename-safety and copied prose only; whether a comment earns its place is review.

## Complexity

gdradon is not used: it converts GDScript to Python and cannot parse some valid GDScript, discards
every expression so boolean operators are never counted, has no threshold or JSON output and exits
zero on failure. Use a parser-based ratchet if complexity gating is wanted.

## Architecture gate

The static gate scans the preload graph and enforces the ownership model: every shipped path has an
owner, each scope has one pure composition root, game access has one home per game-layer service,
the top preload block is the dependency manifest, a service owns its state behind one typed facade
and no file reaches through it, the per-pony host stays a host, and the act keeps its load-bearing
orders. File size is reported as a smell, never as a cap.

The checker owns the rule roster: read it before changing the tree it guards. Every rule has both
directions in its self-test, and the ledgers may only shrink. Its maintenance modes — one rule
group, the graph, the surface audit and the three ledger writers — run on the checker itself.

## Documentation gate

The docs gate checks naming and existence only. A service's doc is `docs/<id>.md`, named after its
directory, non-empty; every `docs/*.md` is a service doc or one of the project docs (`api`, `tests`,
`quality`, `vr`); and no index exists, because the path is the name. A facade's public types carry a
`##` note, and the cross-mod surface's public functions are named in `docs/api.md`.

The gate never judges a doc's content: what a doc owes its reader, that it does not inventory the
code and that comments do not copy it are contracts in `AGENTS.md` and `ARCHITECTURE.md`.

## Shell scripts

Every bash entry point starts with `set -euo pipefail`; the static gate pins that prelude for every
root and shell script. Rely on the options instead of probing dependencies: `set -e` stops at the
failing command and the shell or tool prints the reason. A presence guard is only for a failure that
would otherwise continue unsafely, which is why the parse gate keeps its Godot probe.

A script that must observe a failure captures the status at that call and keeps `-e`. A script
longer than a couple dozen non-empty, non-comment lines is a smell to extract or move — a review
prompt, not a gate.

## Pack report

The pack report says what ships and how big it is. It is a report, not a gate: no gate script runs
it, and only its strict mode turns a pack diff into a failure. A tree report counts source bytes, a
pack report counts packed bytes, where imported textures and audio appear as their imported
artifacts.

Code lines still carry code after a comment is removed, so blank lines and comment blocks do not
count, and the stripping is string-aware. Sizes are printed per language family, with a binary and
sidecar split, and no other section repeats a size.

The report's own self-test runs in the source-checks CI job, and the build job appends the report to
the run's summary, so every run shows the composition of the pack it produced.
