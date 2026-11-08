#!/usr/bin/env bash
# Run the manual unfplap VR lab under Monado and tee the session to ./last-run-vr.log.
# Usage: ./lab-vr.sh [--no-service] [extra godot user args...]
# Godot 4.5 and monado-service must be on PATH; the OpenXR runtime must be installed.
#
# Monado's qwerty driver stands in for the hardware: it presents a virtual HMD and both hand
# controllers, driven by the keyboard and mouse in its own SDL window. Only that window's
# keyboard reaches qwerty, so pose the headset there, then keep the game focused for the lab keys.
# The lab forces room-scale: the standing VR act needs the XR player rig, and a saved
# "Seated: keyboard and mouse" comfort setting would otherwise pick the seated rig.
#   pacman -S monado        |  apt install monado-service libopenxr1-monado libopenxr-loader1

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$ROOT/../.." && pwd)"
RUNTIME_JSON="${XR_RUNTIME_JSON:-/usr/share/openxr/1/openxr_monado.json}"
SERVICE_LOG="$ROOT/last-run-vr-monado.log"
SESSION_LOG="$ROOT/last-run-vr.log"
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/monado_comp_ipc"

no_service=false
if [[ "${1:-}" == "--no-service" ]]; then
	no_service=true
	shift
fi
if [[ "${MONADO_ALREADY:-0}" == "1" ]]; then
	no_service=true
fi

if ! command -v godot >/dev/null 2>&1; then
	printf 'Godot not found on PATH. Install Godot 4.5 or add it to PATH.\n' >&2
	exit 1
fi
if [[ "$no_service" == false ]] && ! command -v monado-service >/dev/null 2>&1; then
	printf 'monado-service not found. Install Monado (monado-service) or start the runtime yourself and pass --no-service.\n' >&2
	exit 1
fi
if [[ ! -f "$RUNTIME_JSON" ]]; then
	printf 'OpenXR runtime manifest not found: %s\n' "$RUNTIME_JSON" >&2
	printf 'Install the Monado runtime package, or set XR_RUNTIME_JSON.\n' >&2
	exit 1
fi

service_pid=""
monado_stdin=""
cleanup() {
	if [[ -n "$monado_stdin" ]]; then
		exec 9>&-
		monado_stdin=""
	fi
	if [[ -n "$service_pid" ]] && kill -0 "$service_pid" 2>/dev/null; then
		kill "$service_pid" 2>/dev/null || true
		wait "$service_pid" 2>/dev/null || true
	fi
}
trap cleanup EXIT INT TERM

if [[ "$no_service" == false ]]; then
	printf 'Monado log: %s\n' "$SERVICE_LOG"
	# monado-service watches stdin for Enter and refuses to start on a non-pollable fd, so it gets
	# an unlinked FIFO held open by fd 9: no tty, no EOF, no shutdown key.
	monado_stdin="$(mktemp -u "${TMPDIR:-/tmp}/unfplap-monado.XXXXXX")"
	mkfifo -m 600 "$monado_stdin"
	exec 9<>"$monado_stdin"
	rm -f "$monado_stdin"
	# qwerty needs the debug GUI window for its virtual devices; FORCE_XCB keeps the VR output in a
	# desktop window instead of taking a direct-mode display, and 100% supersampling suits the iGPU.
	QWERTY_ENABLE=1 \
	XRT_DEBUG_GUI=1 \
	XRT_COMPOSITOR_FORCE_XCB=1 \
	XRT_COMPOSITOR_SCALE_PERCENTAGE=100 \
	monado-service <&9 >"$SERVICE_LOG" 2>&1 &
	service_pid=$!
	for _ in $(seq 1 100); do
		[[ -S "$SOCKET" ]] && break
		if ! kill -0 "$service_pid" 2>/dev/null; then
			printf 'monado-service exited before it was ready:\n' >&2
			tail -n 20 "$SERVICE_LOG" >&2 || true
			exit 1
		fi
		sleep 0.1
	done
	if [[ ! -S "$SOCKET" ]]; then
		printf 'monado-service did not open %s. Last log lines:\n' "$SOCKET" >&2
		tail -n 20 "$SERVICE_LOG" >&2 || true
		exit 1
	fi
else
	printf 'Using the OpenXR service that is already running.\n'
fi

display="${DISPLAY_DRIVER:-}"
if [[ -z "$display" ]]; then
	if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then display=wayland; else display=x11; fi
fi

printf 'VR lab log: %s\n' "$SESSION_LOG"
printf 'Controls: [ / ] fake waist, ; auto stroke, F9 stand behind the mare (see the lab line)\n'

XR_RUNTIME_JSON="$RUNTIME_JSON" \
godot --xr-mode on \
	--display-driver "$display" \
	--path "$PROJECT_ROOT" \
	-- --mod-src unfplap --skip-title \
	--world-id unfplap-test \
	--lab res://mods/unfplap/tests/test_lab_vr.gd \
	--room-scale \
	--require-vr "$@" \
	2>&1 | tee "$SESSION_LOG"
