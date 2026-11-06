# Git workflow

The mod is its own repository at `mods/unfplap`. Run git from there. The game project around it
is a separate repository; never commit game-source changes from the mod repo.

## Every task

1. Inspect state before editing:

   ```bash
   git status
   git log --oneline -12
   ```

2. Decide the commit-sized units before writing code. A commit is one behavior, setting,
   refactor, test or docs change that fits in one sentence.
3. Keep `master` buildable at every commit. No WIP, no failing tests, no TODO-only commits. If a
   task needs intermediate states, use a short-lived local branch and merge it back only when
   every commit passes.
4. Never mix unrelated work. Stage explicitly (`git add <path>` or `git add -p`), never
   `git add -A` or `git commit -a` while another task has edits.
5. Run the checks that cover the change manually before every commit:
   - `scripts/test_all.sh` for any code change;
   - `scripts/smoke.sh` for entry/runtime changes;
   - `./lab.sh` for camera/pose changes; the session is in `last-run.log`, and say it was manual.
6. Commit with one scoped, imperative subject line and no body.
7. Commit locally only. Do not push, fetch, pull or force-push. The maintainer may push and tag;
   CI builds and releases from the remote, but the agent never pushes.

## Commit messages

```text
<scope>: <short imperative summary>
```

One line, at most 72 characters, no trailing period. Reverts use
`revert: <scope>: <summary>` without the quoted original subject. Do not add a body: the reason
belongs in the code comment or the contract doc, not in git.

Scopes: `camera`, `missionary`, `standing`, `thrust`, `hips`, `settings`, `hud`, `dialogue`,
`initiation`, `memory`, `audio`, `cues`, `docs`, `tests`, `build`.

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

## Releases and tags

- Tag only when a release pck is actually built. Do not create intermediate "known-good" tags.
- Build from a clean tagged commit.
- Use an annotated release tag such as `v0.0.4`. The annotation records the target game version,
  build command, commit hash and pck hash.
- Never commit `.pck`, `.godot/`, `*.uid`, logs or user settings (already ignored).
- `git describe --tags --dirty` identifies the source of a build.
- Record the game version in the tag, because the mod repo cannot bisect game changes.

### Release changelog

`changelog.txt` beside `mod.json` is the player-facing release history and ships in the pack.
Before tagging, add the new version section at the top, using the tag as the separator:

```text
v0.1.3
- One high-level feature.
- Another feature.
- Fixed: ...
- Performance: ...
```

Build the section from `git log <previous-tag>..HEAD`. Ignore commits that are only tests, build,
docs or internal debug work. Group multi-commit feature work into one item. Do not add an item for
a feature that was added in an earlier release and only reworked here, and do not advertise a
feature that was added and later removed or reworked away. Put bugfixes and performance work at
the end. The release workflow extracts the section matching the tag as the GitHub release body and
fails when it is missing.

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
