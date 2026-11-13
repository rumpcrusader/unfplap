# Git workflow

The mod is its own repository at `mods/unfplap`. Run git from there. The game project around it
is a separate repository; never commit game-source changes from the mod repo.

## Every task

1. A fresh checkout needs the external runtime assets once:

   ```bash
   scripts/fetch_assets.sh
   ```

   The audio and anatomy files are not tracked. Do this before `--mod-src`, tests, smoke, a lab or
   a build. `scripts/fetch_assets.sh --sources` also restores the V2 Blender file.

2. Inspect state before editing:

   ```bash
   git status
   git log --oneline -12
   ```

3. Decide the commit-sized units before writing code. A commit is one behavior, setting,
   refactor, test or docs change that fits in one sentence.
4. Keep `master` buildable at every commit. No WIP, no failing tests, no TODO-only commits. If a
   task needs intermediate states, use a short-lived local branch and merge it back only when
   every commit passes.
5. Never mix unrelated work. Stage explicitly (`git add <path>` or `git add -p`), never
   `git add -A` or `git commit -a` while another task has edits.
6. Check the change before each commit:
   - `scripts/test.sh <suite>...` for the suites that cover it; use `--all` when it crosses
     several services;
   - `scripts/check.sh` for a quick parse check of the changed scripts;
   - `scripts/smoke.sh` for entry/runtime changes;
   - `./lab.sh` for camera/pose changes; the session is in `last-run.log`, and say it was manual.
7. Run the full gate once per task, when the change is complete:

   ```bash
   scripts/test_all.sh
   ```

   It runs every suite and ends in `TEST_ALL_PASS`. Do not re-run it after every commit or every
   file.
8. Commit with one scoped, imperative subject line and no body.
9. Commit locally only. Do not push, fetch, pull or force-push. The maintainer may push and tag;
   CI builds and releases from the remote, but the agent never pushes.

## Build

Build only when the user asks:

```bash
./build.sh [--out <file.pck>]
```

Success prints `PACK_VERIFY`, `PCK_SHA256` and `MOD_BUILT <path>`. `build.sh` verifies the fetched
runtime set with `scripts/asset_pack.py`, generates the required runtime list with
`scripts/build_manifest.py`, and `pack.gd` requires the packed files to match it. Build from the git
checkout with the fetched assets; a failed check removes the pack. The mod has no script extension.

- `res://tools/modding/build_mod.gd` is not a release path: it ignores `.pckignore` and recurses
  the whole mod folder. Use `build.sh` for anything you ship.
- Do not leave a `.pck` in the source project's live mods folder while testing `--mod-src`; it
  shadows source edits.
- New `.gd` files must be tracked before a build; the pack manifest reads `git ls-files`.

## Commit messages

```text
<scope>: <short imperative summary>
```

One line, at most 72 characters, no trailing period. Reverts use
`revert: <scope>: <summary>` without the quoted original subject. Do not add a body: the reason
belongs in the code comment or the contract doc, not in git.

Scopes: `camera`, `missionary`, `standing`, `thrust`, `hips`, `settings`, `hud`,
`dialogue`, `initiation`, `memory`, `audio`, `cues`, `docs`, `tests`, `build`, `ci`,
`release`, `anatomy`, `vr`.

Never use `WIP`, `fixes`, `stuff`, `misc` or `cleanup` as the whole message: say what changed.

Examples:

```text
missionary: start the shot at the old max lean point
settings: stop clamping tuning values in the consumers
revert: standing: follow the dock in the offer
```

## Bisect

Every `master` commit passes. There are no intermediate known-good tags; use a release tag or
an explicit commit hash as the good endpoint.

1. Reproduce with a deterministic command. If no test covers it, write the smallest failing test
   or a temporary standalone check. A new test added at the tip does not exist in older commits,
   so bisect with a temporary copy of that test or a check that works at every commit.
2. Start:

   ```bash
   git bisect start
   git bisect bad
   git bisect good <release-tag-or-commit>
   ```

3. Run the predicate:

   ```bash
   git bisect run scripts/test_all.sh
   ```

   or a targeted suite for speed.
4. Fix, commit the fix with the regression test, then `git bisect reset`.
5. Keep the regression test as the permanent guard.

Docs-only commits do not need bisecting; use `git bisect skip` if one is picked.

## Releases

Use `/release`. The runbook is `.opencode/skills/release/SKILL.md`. The agent prepares and
validates locally; the maintainer reviews the release commit, pushes it and the annotated tag, and
handles CI and the community store.

## What not to do

- No `git add -A` or `git commit -a` while another task is in the tree.
- No push, fetch, pull, force-push or history rewrite.
- No combined "cleanup" commits. Split mechanical, behavioral and docs changes.
- No generated artifacts or local settings committed.

## Quick regression archaeology

```bash
git log --oneline -20
git log -S "<constant or function>" --oneline
git log -G "<regex>" --oneline -p
git blame <file>
git show <commit>
```

Use commit subjects for intent; code comments state invariants, not history.
