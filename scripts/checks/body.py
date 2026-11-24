"""The body-change fan-out, the one resume, the provider policy and the runtime binding."""
from __future__ import annotations

import re

from .context import ROOT, read_text, shipped_sources
from .failure import Failure, rel
from .text import call_lines, function_body

# The five body-bound systems `body_change.wire()` builds and registers. The entry names none of
# them: a new binding adds a preload to the service, not to the composition root.
BODY_BINDINGS = (
    "body_change/anatomy_binding.gd",
    "body_change/runtime_binding.gd",
    "body_change/lod_binding.gd",
    "body_change/garment_binding.gd",
    "body_change/smack_binding.gd",
)


def check_body(failure: Failure) -> None:
    runtime = read_text(str(ROOT / "runtime.gd"))
    session_text = read_text(str(ROOT / "act" / "session.gd"))

    # One body-change fan-out: only the service dispatches to registered body bindings, through
    # its one bind/refresh/unbind loop each. A second dispatcher would bypass the form store.
    for needle in ("binding.bind_body(", "binding.refresh_body(", "binding.unbind_body("):
        callers = [rel(path) for path in shipped_sources()
                   if needle in read_text(str(path))]
        if callers != ["body_change/api.gd"]:
            failure.add("%s must only be dispatched from body_change/api.gd (found %s)" % (
                needle, ", ".join(callers) or "none"))
    service = read_text(str(ROOT / "body_change" / "api.gd"))
    for name in ("_notify_bind", "_notify_refresh"):
        if service.count("func %s(" % name) != 1:
            failure.add("body_change/api.gd must define one %s()" % name)

    # One resume: the swap module keeps the only resume path, and adoption never resumes itself.
    swap_path = ROOT / "act" / "swap.gd"
    if not swap_path.is_file():
        failure.add("missing act/swap.gd: it owns the body-swap seams and the one resume")
        swap_text = ""
    else:
        swap_text = read_text(str(swap_path))
    if len(re.findall(r"^func resume\(", swap_text, re.MULTILINE)) != 1:
        failure.add("act/swap.gd must define exactly one resume()")
    for path in shipped_sources():
        if path == swap_path:
            continue
        if "_swap.resume(" in read_text(str(path)):
            failure.add("%s must not resume a body swap" % rel(path))
    if ".resume(" in function_body(runtime, "adopt_body"):
        failure.add("adopt_body() must not resume; the watcher owns the one resume")

    # The provider policy owns the offer prompt and the reveal magnitudes. The act handover only
    # asks the typed policy and executes its generic effects.
    handover = read_text(str(ROOT / "body_change" / "act.gd"))
    for name in ("FORM_OFFER_PROMPT", "FORM_REVEAL_HEAT", "FORM_REVEAL_PEAK_SCORE"):
        if name in runtime or name in handover:
            failure.add("the act handover must not own the provider policy value %s" % name)
    offer = function_body(handover, "offer_tick")
    for needle in (".should_offer(", ".offer_prompt()"):
        if needle not in offer:
            failure.add("body_change/act.gd offer_tick() must ask the typed policy for %s" % needle)
    if ".on_reveal(" not in function_body(handover, "_commit_form_reveal"):
        failure.add("_commit_form_reveal() must execute the typed policy's on_reveal()")
    if ".on_offer_accepted(" not in function_body(handover, "_apply_offer_accepted"):
        failure.add("_apply_offer_accepted() must execute the typed policy's on_offer_accepted()")

    # One runtime binding: the body-change service builds it with the rest of the chain, the
    # runtime exposes the two typed hooks, and the binding never runs the act exit or a second
    # resume.
    binding_path = ROOT / "body_change" / "runtime_binding.gd"
    if not binding_path.is_file():
        failure.add("missing body_change/runtime_binding.gd")
    else:
        binding = read_text(str(binding_path))
        if 'extends "res://mods/unfplap/shared/body_binding.gd"' not in binding:
            failure.add("body_change/runtime_binding.gd must extend the typed body binding")
        if 'return "runtime"' not in binding:
            failure.add('body_change/runtime_binding.gd must name itself "runtime"')
        for needle in ("_end_session(", "_resume_after_body_swap("):
            if call_lines(binding, needle):
                failure.add("body_change/runtime_binding.gd must not call %s" % needle)
    # The service builds every binding from the facades the entry hands it, so a new body-bound
    # system adds a preload and a register call to the service and no line to the entry.
    service_source = read_text(str(ROOT / "body_change" / "api.gd"))
    if "func wire(" not in service_source:
        failure.add("body_change/api.gd must build its bindings in wire()")
    for needle in BODY_BINDINGS:
        if service_source.count(needle) != 1:
            failure.add("body_change/api.gd must name the body binding %s once" % needle)
    main_source = read_text(str(ROOT / "main.gd"))
    for number, line in enumerate(main_source.splitlines(), start=1):
        if "_binding.gd" in line or "register_binding" in line:
            failure.add(
                "main.gd:%d builds a body binding; body_change.wire() owns the chain" % number)
    for name in ("bind_body_services", "refresh_body_services"):
        if len(re.findall(r"^func %s\(" % name, session_text, re.MULTILINE)) != 1:
            failure.add("act/session.gd must define exactly one %s()" % name)
