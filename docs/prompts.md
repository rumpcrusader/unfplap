# Prompt text

Every word the mod sends to a model lives in one shipped document, `settings/prompts.json`, and is
rendered by one module, `shared/prompt_text.gd`. No other file parses a placeholder, walks a prompt
part or keeps a copy of the prose.

## Scope

This contract covers:

- the document's path, ownership and the groups it is divided into;
- the four node kinds and the JSON that selects each one;
- the placeholder rules: parts, slots, the graph and what makes a document invalid;
- the renderer's API and its rendering rules;
- which module reads which group, and the graph test that guards the document.

It does not cover the prompt a service wraps around the text: the payload shape, the parser of the
model's reply and when a call happens belong to that service's contract (`docs/dialogue.md`,
`docs/initiation.md`, `docs/negotiation.md`, `docs/memory.md`, `docs/summary.md`). The settings
framework and the other shipped documents are `docs/settings.md`.

## Ownership

`settings/prompts.json` is shipped data, not code: it is tracked, packed, read-only in a build and
parsed once per process by `shared/defaults_data.gd`. It is never copied into a player file, never
written by the mod, and it is not a promotion target for `scripts/settings_sync.py`; a provider
cannot override it (`docs/api.md`).

`shared/prompt_text.gd` is a pure shared module: no Node, clock, file or service preload. It owns
graph construction, validation and rendering, and it is the only implementation of all three. A
consumer names a node by its dotted id and passes the slot values; it never formats a prompt
string itself.

## Document

```json
{
	"version": 1,
	"act": { ... },
	"ask": { ... },
	"classify": { ... },
	"history": { ... },
	"relationship": { ... },
	"cycle": { ... },
	"beats": { ... },
	"body_change": { ... }
}
```

The document is grouped by feature, not by consumer, so one group serves several modules. `version`
is document metadata; `validate()` skips it and the renderer never walks it.

| Group | Read by | Holds |
|---|---|---|
| `act` | `dialogue/service.gd`, `dialogue/prompts.gd`, `dialogue/utterance.gd`, `memory/service.gd`, `summary/score.gd` | cue, utterance, climax and early-end lines, the bystander line, the normal note, the state line, the private seeds, the fresh angles and the speech feel |
| `ask` | `initiation/prompts.gd` | the context and purpose composites, the situation text, the openings, the privacy modes, the heat sentence and the crowd hint |
| `classify` | `negotiation/prompts.gd`, `initiation/reasoning.gd` | the classifier and reasoning instructions |
| `history` | `shared/act_history.gd` | the stored-history tiers and the idle-scan lines |
| `relationship` | `shared/relationship_cue.gd` | the stage phrases, the tone instructions and the shared-memory frame |
| `cycle` | `shared/cycle.gd` | the heat and diestrus notes |
| `beats` | `summary/score.gd` | the afterglow pools, one per grade |
| `body_change` | `integrations/changelings_policy.gd` | the provider's offer line |

A consumer reads a group through `DEFAULTS.prompts_block("<prefix>")` and renders the node it
needs. A node the file does not hold renders as an empty string; a consumer that needs text decides
whether to skip the call, and `dialogue` does.

## Node kinds

A node is one of four kinds, decided by its JSON shape:

| Kind | Shape | Meaning |
|---|---|---|
| Composite | an object with `template` and `slots`; every other key is a part | the template's names select parts and slots, and the template string fixes their order |
| Variant map | an object without `template` and without `slots` | its values are strings or composites, selected by key (`seed`, `body`, `stages`, `openings`, ...) |
| Pool | an array of strings | one line is picked by code (`angles`, `beats`); nothing is substituted |
| Plain string | a string | one finished line; it may not contain a placeholder |

A composite's sibling keys are its **parts**. A part is a plain string or another composite; a
nested composite brings its own `template`, `slots` and parts and is validated in that scope.

A composite declares its **slots**: the names code supplies as values. `slots` is a list of names
and its order carries no meaning; the template string is the only source of order.

```json
"cue": {
	"slots": ["seed", "state", "relationship"],
	"template": "{moment} {state_line} {relationship_line} {instruction}",
	"moment": "During sex with Anon, the private moment is: {seed}",
	"state_line": "Current moment: {state}.",
	"relationship_line": "Private relationship note: {relationship}.",
	"instruction": "Say ONE short line in your own voice."
}
```

## Placeholders and the graph

A placeholder is `{name}` where the name matches `[a-z_][a-z0-9_]*`. Inside one composite:

- a name is either a **part** (a sibling key, so the graph has an edge to that node) or a
  **declared slot** (a leaf the caller fills); a name that is neither fails;
- a name may not be both a part and a slot, so a forwarding part such as `"memory": "{memory}"` is
  not allowed; the template references the `memory` slot directly;
- the part-reference graph must be a directed acyclic graph: a cycle fails;
- every part must be reachable from the template, and every declared slot must be referenced;
- a plain string may not reference anything, because nothing supplies its names.

Validation reports every failure it finds, with the dotted path of the node:

| Failure | Meaning |
|---|---|
| unknown reference | a name that is neither a part nor a declared slot |
| cycle through a name | the part graph is not a DAG |
| both a part and a slot | one name declared in both roles |
| unreachable | a sibling key no template reaches |
| unused slot | declared but never referenced |
| missing template, missing slots | a composite without one of its two required keys |
| plain string references a name | a leaf with a placeholder it cannot fill |
| not a prompt node, not a prompt string | a number, object or nested array where text belongs |

The graph is per composite: a nested composite's parts and slots are its own, and a variant map
does not add edges.

## Renderer

| Function | Returns | Meaning |
|---|---|---|
| `validate(document)` | `Array[String]` | every structural failure in the document, or an empty array |
| `render(prompt, values)` | `String` | the fully rendered prompt; a plain string is a raw template whose names are all slots |
| `render_document(document, values_by_id)` | `Dictionary` | dotted id to rendered text for every string leaf and composite, for tests and debug |

`render()` returns `""` for a composite that is malformed or not a DAG, and for any node that is
neither a string nor a composite. It never raises.

Rendering rules:

- a part is dropped, with its own whitespace, when any slot it references is empty after trimming;
  a direct slot token in the template renders as empty and the rest of the line stays, so a state
  line keeps its shape when one value is missing;
- substitution is recursive with per-render memoisation and a depth guard; a runaway chain stops at
  the guard and the part is dropped rather than recursing;
- runs of spaces and tabs inside a line collapse to one, newlines inside a part survive, and each
  line's edges are trimmed;
- a valid graph leaves no `{}` in the output;
- `render_document()` expands composites and collapses string leaves but skips pools, so it shows
  what the model would see, not which line a pool would pick.

The renderer is stateless: two calls with the same prompt and values return the same text, and no
call keeps a rendered string.

## Contributing a prompt

1. Add the node to `settings/prompts.json`, in the group of the feature it belongs to.
2. Give a composite its `template` and `slots`, then one sibling per part. A composite big enough
   to nest (a body line with a name, a history line with remembered text) nests instead of
   inventing a second flat id.
3. Name the node from the consumer and pass every declared slot; a new slot is a new value at the
   use site, not a second formatter.
4. Add the id to `tests/test_prompts.gd`'s `CONSUMER_IDS` when a consumer starts naming it, so a
   rename cannot pass unnoticed.
5. Document the behaviour in the owning service's contract, not the prose. Never name a shipped
   sentence in a doc or a comment: it lives in the file.

A new id is a data change plus one consumer constant; a new consumer formatter is a review
failure, because it would be a second prompt implementation.
