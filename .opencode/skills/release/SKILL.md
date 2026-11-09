---
name: Release
description: Prepare and validate an Unfplap release. Use only when the user explicitly invokes /release.
metadata:
  opencode/autoinvoke: false
---

# Unfplap release

Run from the mod repository root (`mods/unfplap`). The agent prepares and validates; the user
reviews, pushes the commit and annotated tag, and handles the store. The release is done when the
tag is pushed.

## 0. Assets

The act audio and anatomy files are not tracked. They are fetched from one archive on pone.rs and
packed at build time.

- In a fresh checkout, run `scripts/fetch_assets.sh` before anything else.
- If audio or anatomy changed since the committed archive, put the V2 Blender source in
  `sources/anatomy/mare_bits_v2.blend` and run `scripts/pack_assets.sh --upload`. Commit
  `scripts/asset_pack.json` in its own asset commit before the release metadata.
- Do not re-upload an unchanged asset set. The committed URL and hash are reused.
- `scripts/asset_pack.json` is the contract: archive URL, archive SHA-256 and the per-file runtime
  manifest. Never hand-edit it. `scripts/fetch_assets.sh` and `build.sh` both verify it.
- The archive's `sources/` tree is for editing and is never packed. The `runtime/` tree is packed.
- `scripts/check_release.sh` verifies the local runtime set before tests and the build.

## 1. Start

- `git status --short` must be empty.
- Note the current branch; CI requires the tag to be on the repository default branch.
- Read `mod.json` and `project.godot` (`config/version`).
- Run `scripts/prepare_release.sh` with no argument to print the current version, target game,
  last tag and commit count.
- Ask the user for the next version (patch/minor/major) and confirm the target game.
- If `project.godot` and `mod.json.game_version` differ, stop. Update compatibility in a separate
  commit; do not mix it into the release commit.

## 2. Prepare

Run `scripts/prepare_release.sh <version>`. It updates `mod.json.version`, inserts a changelog
section with `- TODO`, and prints the commits since the previous tag.

Draft the changelog from those commits:

- Ignore tests, build, docs and internal debug work.
- Group multi-commit feature work into one bullet.
- Do not re-advertise a feature from an earlier release. A major player-visible rework may be one
  `Reworked:` bullet.
- Put fixes and performance work last.
- One line per bullet, no wrapping, no `TODO`.

Show the changelog to the user.

## 3. Commit

Stage only the release metadata:

```bash
git add mod.json changelog.txt
git commit -m "build: release <version>"
```

Do not include unrelated code or docs. If anything else changed, stop and split it into an earlier
commit.

## 4. Validate

Run `scripts/check_release.sh`. It checks the release commit, versions, changelog, target game and
the fetched resource manifest, runs the test suites, and builds a self-verifying preflight pack.
It requires Godot 4.5.2 and moves installed `unfplap*.pck` files to `.pck.bak` before the smoke
test. Show its full review packet; do not summarize away warnings.

Stop. Ask the user to:

- review the release commit and changelog;
- install `dist/unfplap-<version>.pck` and run the relevant lab pass (camera, pose and anatomy
  changes always need this);
- confirm the pack loads in a fresh world and an existing save.

If the user wants changes, amend the local commit and rerun `check_release.sh`. Never amend after
the commit has been pushed.

## 5. Hand off

When the user approves, give the exact push and tag commands from the review packet. Do not run
them. The user pushes the commit to the repository default branch, creates the annotated tag
`v<version>` on the reviewed commit, and pushes the tag.

The release is done when the tag is pushed. Do not wait for CI, do not poll the store, and do not
create a release state file.

## 6. After the tag

Give this reminder, then stop:

1. Confirm the GitHub release asset and its `.sha256`; install that exact pck once.
2. Run `publish-store` as a dry run, then submit.
3. Approve `mod-store`; the store admin approves the row.

The store dry run previews the pone.rs mirror but does not write the store.

## Failure

- Before the tag is pushed: fix, amend the local commit, rerun `check_release.sh`.
- After the tag is pushed: never move or reuse the tag. Publish a new patch release.
- If `build.sh` reports `ASSETS_MISSING`, `ASSETS_STALE` or `ASSETS_EXTRA`, run
  `scripts/fetch_assets.sh`. If the change is intentional, repack and upload the archive, commit
  `scripts/asset_pack.json`, and rerun the check.
- If `scripts/pack_assets.sh --upload` cannot verify the served archive, stop. Do not hand-write
  the URL or hash into `scripts/asset_pack.json`.
- If `build.sh` fails, fix the pack; do not work around the verifier.
