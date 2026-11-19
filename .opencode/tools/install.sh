#!/usr/bin/env bash
# Install gd-lsp-mcp for OpenCode: copy the server and merge its MCP entry.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
mkdir -p "$config/tools"
install -m 0755 "$here/gd-lsp-mcp" "$config/tools/gd-lsp-mcp"
python3 - "$config/opencode.json" "$config/tools/gd-lsp-mcp" <<'PY'
import json, os, sys
path, tool = sys.argv[1], sys.argv[2]
cfg = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
cfg.setdefault("mcp", {}).setdefault("servers", {})["gdlsp"] = {
    "type": "local", "command": ["python3", tool], "codemode": False,
    "timeout": {"startup": 30000, "execution": 60000},
}
with open(path + ".tmp", "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2); f.write("\n")
os.replace(path + ".tmp", path)
PY
"$config/tools/gd-lsp-mcp" --self-test
