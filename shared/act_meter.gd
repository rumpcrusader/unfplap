extends RefCounted
## What one act's readiness counted, taken once when the act produces its verdict. Readiness is the
## only writer and the scoring record reads it afterwards; the dislike map is handed over as a copy,
## so a live act can never change a score.

## The scoring counters, one per thing the grade rewards or punishes.
var thrusts: int
var pony_climaxes: int
var talk_liked: int
var talk_dislikes: int
var touches_liked: int
var touch_dislikes: Dictionary
var player_lines: int
var intensity_total: int
var intensity_right: int
var pattern_total: int
var pattern_right: int

## The peak's inputs: how strongly the act landed, how much of it matched, and what he last said.
var peak_satisfaction: float
var both_matches: int
var dislikes: int
var liked_touch: int
var liked_talk: int
var player_talk: String
