"""The act's structural invariants: one teardown, the ledgers' order and the pose's scope."""
from __future__ import annotations

import re

from .context import ROOT, read_text, shipped_sources
from .failure import Failure, rel
from .text import _code_lines, enclosing_function, function_body, function_offsets

ACT_EXIT_CALLS = (
    "_end_session(",
    "_free_pose(",
    "release_pose(",
    "_unlock_player(",
    "_restore_pony_bones(",
    "_restore_camera(",
    "_restore_look(",
    "_release_nav(",
)
TEARDOWN_STEPS = (
    "_restore_camera(",
    "_restore_look(",
    "_release_nav(",
    "_free_pose(",
    "_unlock_player(",
)
POSE_ACT_EXIT_CALLS = (
    "_end_session(",
    "_unlock_player(",
    "_restore_pony_bones(",
    "_restore_camera(",
    "_restore_look(",
    "_release_nav(",
    "_free_pose(",
)
POSE_LEDGER_ORDER = (
    "context.pose.leave_pose_start()",
    "context.presentation.clear_presentation()",
    "context.camera.end_lean_action()",
    "context.hands.reset()",
    "context.kiss.reset()",
    "context.integrations.reset()",
    "context.hold.release_all_beats()",
    "context.standing_anon.remove()",
    "context.pose.leave_pose_body()",
    "context.reactions.end_act()",
    "context.pose.release_pose()",
)
POSE_FANOUT_ORDER = (
    "context.pose",
    "context.camera",
    "context.hands",
    "context.kiss",
    "context.anatomy",
)
# The start ledger's recipe, in the order the act depends on: the presentation guard, the stool,
# the borrows, the pose build, the player frame, the camera open, the audio,
# POSING_IN and the HUD card. `begin_pose_in()` precedes `show_act()` because the HUD reads the
# live state it sets.
START_LEDGER_ORDER = (
    'POSE_SPECS.start_setup(pose) == "standing_place"',
    "session.reset_stool_state()",
    "session.posture_owned = false",
    "session.profile = SETTINGS.template_for(",
    "session.bed = context.gate.resolve_bed(",
    "var setup_name := POSE_SPECS.start_setup(pose)",
    "_build_pose()",
    "context.frame.begin(",
    "context.camera.begin_act(",
    "context.audio.begin_act(",
    "session.begin_pose_in()",
    "context.hud.show_act(context.facts)",
)
# The pose ledger's callers: the one act exit, the new-act prep and the body-swap suspension.
# A new caller is a design decision, so the set is exact and compared both ways.
POSE_LEDGER_CALLERS = {
    ("act/exit.gd", "run"),
    ("act/start.gd", "_build_pose"),
    ("act/swap.gd", "release_swap_pose"),
}
# The act's player frame and its view each have one writer. Each row is a write token and the files
# allowed to carry it, and the scan is compared both ways: a second writer fails, and a row no file
# carries any more is stale. The accessor's momentary control lock is a base-game hold, not the frame.
ACT_STATE_WRITES = {
    'set("_stand_eye"': {"world/game.gd": "the eye-line accessor writes the frame's stance"},
    'set("_eye_height"': {"world/game.gd": "the eye-line accessor writes the frame's stance"},
    'call("_set_eye_y"': {"world/game.gd": "the eye-line accessor writes through the rig's setter"},
    'set("controls_locked"': {
        "world/game.gd": "a base-game call with his controls released",
    },
    'set("_pitch"': {
        "world/game.gd": "the pitch accessor writes his own look",
    },
    'body.global_position = ': {"act/frame.gd": "the frame places him"},
    'body.rotation.y = ': {
        "act/frame.gd": "the base facing",
        "camera/view.gd": "the live lean turns his own look",
    },
    '_player.rotation.y = ': {"act/frame.gd": "the frame restores his captured look"},
    'host.pony.global_transform = ': {"act/frame.gd": "the frame restores the scene it found"},
    'rig.pony.reset_motion(': {"act/frame.gd": "the player-pony start places her"},
    'context.pose.write_render_frame(': {
        "act/view.gd": "the render-time act body write",
        "act/frame.gd": "the frame places the act body once",
    },
    '_missionary_view.global_position = ': {"camera/view.gd": "the one act view"},
    '_missionary_view.global_basis = ': {"camera/view.gd": "the one act view"},
    '_missionary_view.current = ': {"camera/view.gd": "the one act view"},
    'camera.position = ': {"camera/view.gd": "the player camera's live offset"},
    'camera.position.y = ': {"camera/view.gd": "the player camera's live offset"},
    'camera.position.z -=': {"camera/view.gd": "the player camera's live offset"},
    'camera.position.x +=': {"camera/view.gd": "the player camera's live offset"},
    'camera.rotation.z = ': {"camera/view.gd": "the live lean roll"},
    'camera.rotation.x = ': {"camera/view.gd": "the live lean pitch"},
    'view.rotation.x = ': {
        "act/frame.gd": "the base aim and its restore",
        "camera/view.gd": "the live lean pitch on the player camera",
    },
}


def check_act(failure: Failure) -> None:
    exit_path = ROOT / "act" / "exit.gd"
    if not exit_path.is_file():
        failure.add("missing act/exit.gd: it owns the one teardown and the pose ledger")
        exit_text = ""
    else:
        exit_text = read_text(str(exit_path))

    # One teardown: `act/exit.gd:run()` is the only scene-restoring body, and the exit's own
    # routes plus the consent stop are its only callers. No route repeats a teardown step.
    if exit_text and len(re.findall(r"^func run\(", exit_text, re.MULTILINE)) != 1:
        failure.add("act/exit.gd must define exactly one run()")
    for name in ("finish_restore", "restore_now", "force_stop"):
        body = function_body(exit_text, name)
        if not body:
            failure.add("act/exit.gd is missing %s()" % name)
            continue
        if "run(" not in body:
            failure.add("act/exit.gd:%s() must end through run()" % name)
        for call in TEARDOWN_STEPS:
            if call in body:
                failure.add("act/exit.gd:%s() must not call %s directly" % (name, call))
    if "restore_now()" not in function_body(exit_text, "force_stop"):
        failure.add("act/exit.gd:force_stop() must restore through restore_now()")
    teardown_callers: set[tuple[str, str]] = set()
    for path in shipped_sources():
        text = read_text(str(path))
        offsets = function_offsets(text)
        for match in re.finditer(r"(?<![\w])run\((?:true|false|rejoin_cuddle)\)", text):
            line = text[text.rfind("\n", 0, match.start()) + 1:match.start()]
            if line.lstrip().startswith(("#", "func ")):
                continue
            teardown_callers.add((rel(path), enclosing_function(offsets, match.start())))
    expected_callers = {("act/exit.gd", "abort"), ("act/exit.gd", "finish_restore"),
                        ("act/exit.gd", "restore_now"), ("act/exit.gd", "force_stop"),
                        ("act/consent.gd", "stop_with_her")}
    for caller in sorted(teardown_callers - expected_callers):
        failure.add("the one teardown has an unexpected caller: %s:%s" % caller)
    for caller in sorted(expected_callers - teardown_callers):
        failure.add("the one teardown is missing its caller: %s:%s" % caller)
    # The act session keeps the one-line stop delegate for the entry, `ponies` and the suites.
    session_path = ROOT / "act" / "session.gd"
    session_text = read_text(str(session_path)) if session_path.is_file() else ""
    stop_body = function_body(session_text, "force_stop")
    stop_lines = [line.strip() for line in stop_body.splitlines()[1:]
                  if line.strip() and not line.strip().startswith("#")]
    if stop_lines != ["exit.force_stop()"]:
        failure.add("act/session.gd:force_stop() must be the one-line exit.force_stop() delegate")

    # The start ledger's recipe keeps its order; the checker reads the tokens, not the prose.
    start_path = ROOT / "act" / "start.gd"
    if not start_path.is_file():
        failure.add("missing act/start.gd: it owns the ordered start")
    else:
        run_body = function_body(read_text(str(start_path)), "run")
        cursor = 0
        for step in START_LEDGER_ORDER:
            at = run_body.find(step, cursor)
            if at < 0:
                failure.add("act/start.gd run() must keep %s at its position" % step)
                break
            cursor = at + len(step)

    # The pose ledger keeps its pose-scope steps and act-scope resets in their current order, and
    # only the act exit, the new-act prep and the body-swap suspension call it.
    free = function_body(exit_text, "free_pose")
    cursor = 0
    for call in POSE_LEDGER_ORDER:
        at = free.find(call, cursor)
        if at < 0:
            failure.add("act/exit.gd free_pose() must keep %s at its position" % call)
            break
        cursor = at + len(call)
    ledger_callers: set[tuple[str, str]] = set()
    for path in shipped_sources():
        text = read_text(str(path))
        offsets = function_offsets(text)
        for match in re.finditer(r"(?<![\w])free_pose\(\)", text):
            line = text[text.rfind("\n", 0, match.start()) + 1:match.start()]
            if line.lstrip().startswith(("#", "func ")):
                continue
            ledger_callers.add((rel(path), enclosing_function(offsets, match.start())))
    for caller in sorted(ledger_callers):
        if caller not in POSE_LEDGER_CALLERS:
            failure.add("the pose ledger has an unexpected caller: %s:%s" % caller)
    for caller in sorted(POSE_LEDGER_CALLERS):
        if caller not in ledger_callers:
            failure.add("the pose ledger is missing its caller: %s:%s" % caller)
    release_calls = set()
    for path in shipped_sources():
        for line in read_text(str(path)).splitlines():
            if "release_pose()" in line and not line.lstrip().startswith(("#", "func ")):
                release_calls.add(rel(path))
    if release_calls != {"act/exit.gd"} or "release_pose()" not in free:
        failure.add("release_pose() must be called only from the pose ledger")

    # The frame schedule advances the pose edge before the view refresh, then fans the change out;
    # the fixed owner order is the seam, and neither body is a second teardown. The schedule is
    # `act/tick.gd`'s; `act/session.gd` is the entry that forwards one frame to it.
    tick_path = ROOT / "act" / "tick.gd"
    session_path = ROOT / "act" / "session.gd"
    if not tick_path.is_file():
        failure.add("missing act/tick.gd: it owns the ordered frame schedule")
        tick_text = ""
    else:
        tick_text = read_text(str(tick_path))
    if session_path.is_file():
        for name in ("tick", "render"):
            body = function_body(read_text(str(session_path)), name)
            if "ticker." not in body:
                failure.add("act/session.gd:%s() must forward to the frame schedule" % name)
    tick = function_body(tick_text, "_tick")
    tick_at = tick.find("context.pose.tick(delta)")
    facts_at = tick.find("session.refresh_view()")
    fanout_at = tick.find("_fanout()", facts_at if facts_at >= 0 else 0)
    if tick_at < 0 or facts_at < 0 or tick_at > facts_at:
        failure.add("act/tick.gd:_tick() must tick the pose before the view refresh")
    if facts_at < 0 or fanout_at < facts_at:
        failure.add("act/tick.gd:_tick() must fan the pose change out after the view refresh")
    fanout = function_body(tick_text, "_fanout")
    cursor = 0
    for owner in POSE_FANOUT_ORDER:
        at = fanout.find(owner, cursor)
        if at < 0:
            failure.add("act/tick.gd:_fanout() must name %s in order" % owner)
            break
        cursor = at + len(owner)
    for name, body in (("_tick", tick), ("_fanout", fanout)):
        for call in ACT_EXIT_CALLS:
            if call in body:
                failure.add("act/tick.gd:%s() must not call %s" % (name, call))

    # The pose system never reaches an act exit; its scope is the live pose and its own release.
    for path in (ROOT / "poses").rglob("*.gd"):
        text = read_text(str(path))
        for call in POSE_ACT_EXIT_CALLS:
            if call in text:
                failure.add("%s must not reach the act exit: %s" % (rel(path), call))


def check_act_owners(failure: Failure) -> None:
    """The act's player frame and its view have one writer each.

    The frame places, stances and restores Anon; the view applies the live look and writes the act
    view node. One owner per state is the property the scattered camera setup lost, so the write
    tokens are checked as an allow-list in both directions.
    """
    found: dict[str, set[str]] = {token: set() for token in ACT_STATE_WRITES}
    for path in shipped_sources():
        text = _code_lines(read_text(str(path)))
        for token in ACT_STATE_WRITES:
            if token in text:
                found[token].add(rel(path))
    for token, owners in ACT_STATE_WRITES.items():
        for name in sorted(found[token] - set(owners)):
            failure.add(
                "%s writes the act's player/view state (%s); %s owns it" % (
                    name, token, ", ".join(sorted(owners))))
        for name, reason in sorted(owners.items()):
            if name not in found[token]:
                failure.add("the act write row %s (%s) is stale for %s" % (token, reason, name))
