# gd-lsp-mcp

Exact GDScript navigation for coding agents, from Godot's own language server.

The server is a supervisor, an LSP client and an MCP relay in one stdlib-only Python file. It
owns no GDScript knowledge: `godot --headless --editor --lsp-port N` parses the project, and
this file answers `outline`, `hover`, `definition`, `references` and `diagnostics` from it.

It is optional development tooling. The mod never depends on it, and the pack never contains
it (`.opencode/` is excluded by `scripts/build_manifest.py`).

## Requirements

- Godot 4.5 on `PATH` (or `GDLSP_GODOT` pointing at it).
- Python 3.10 or newer.
- OpenCode 2.x with MCP support.

## Install

```bash
.opencode/tools/install.sh
```

The script copies the server to `~/.config/opencode/tools/gd-lsp-mcp`, merges the `gdlsp`
entry into `~/.config/opencode/opencode.json` (preserving every other key) and runs the
self-test. Re-run it after pulling a newer copy.

Manual install: copy the file anywhere, then add this under `mcp.servers` in the OpenCode
config, with the absolute path:

```json
"gdlsp": {
  "type": "local",
  "command": ["python3", "/home/you/.config/opencode/tools/gd-lsp-mcp"],
  "codemode": false,
  "timeout": { "startup": 30000, "execution": 60000 }
}
```

`codemode: false` exposes the tools directly instead of only through Code Mode. The timeouts
cover the first call, which boots the editor.

## Tools

Positions are 1-based line and column, matching `read` and `grep -n`. Every position tool also
accepts `symbol` (a literal identifier, first match in the file), so no column counting.

| Tool | Answers |
|---|---|
| `gd_outline` | every function, constant, variable, signal and nested class with its line range; `filter` (regex), `docs` (first doc line), `max` |
| `gd_hover` | signature and doc comment of the symbol at a position |
| `gd_definition` | where the symbol is declared, across files |
| `gd_references` | every real reference (no comments, no strings); `include_declaration`, `max` |
| `gd_diagnostics` | errors and warnings for one file, or for `mods/unfplap/**` with no path |
| `gd_status` | the daemon for this project: root, port, pid, uptime, RSS, open buffers |
| `gd_shutdown` | stop the daemon and reclaim its memory |

## Cost

One headless editor per Godot project root, kept alive between sessions: about 3.5 GB RSS and
12% of one core while idle. Warm calls are 0.02–0.3 s; the first call after a reboot takes
about 12 s. `gd_status` shows the cost, `gd_shutdown` reclaims it.

## Limits

- No project-wide symbol search: Godot advertises `workspace/symbol` but does not implement it.
  `grep` still finds a name; `gd_definition` and `gd_hover` resolve it once found.
- OpenCode 2.2.0 has no LSP client, so there is no diagnostics-on-edit. Diagnostics are pulled
  with `gd_diagnostics`; the `--stdio-relay` mode is for editors that do speak LSP over stdio.
- The daemon is the editor's view of the project. The server sends the current file text before
  every query, so unsaved edits are visible, but a file changed outside the editor is only
  re-read when a query touches it.

## Test

```bash
gd-lsp-mcp --self-test          # throwaway project in /tmp, 22 checks
gd-lsp-mcp --probe gd_hover '{"path": "runtime.gd", "symbol": "anatomy_on"}'
```

## Use in another mod

The server is generic: it discovers the project root by walking up to `project.godot`. Copy
this directory into another mod, or install it once globally and every Godot project on the
machine gets the tools.
