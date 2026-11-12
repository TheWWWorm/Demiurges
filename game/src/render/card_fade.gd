class_name ELCardFade
extends RefCounted
## Campaign pictures of both games (campaign choice, the first game's branch
## choice): each picture keeps an opacity that moves towards its target by 10
## (of 255) every frame. A picture is drawn at 0x76 until it is chosen, and the
## chosen one rises to 0xe6 while the others fall back. The picture under the
## pointer is drawn 0x19 brighter at once (at most 255). The pictures are
## blended over the panel, and the second game's captions follow their card.
## The original steps once per menu frame; the remake steps at 60 per second.

const DIM := 0x76
const LIT := 0xe6
const HOVER := 0x19
const STEP := 10
const STEPS_PER_SECOND := 60.0

## Opacity now (0..255) and the opacity it moves towards.
var now := float(DIM)
var target := float(DIM)

## Chooses (or releases) the picture; `at_once` skips the fade.
func choose(chosen: bool, at_once := false) -> void:
	target = LIT if chosen else DIM
	if at_once: now = target

## Moves the opacity towards its target; true while it is still moving.
func advance(delta: float) -> bool:
	now = move_toward(now, target, STEP * STEPS_PER_SECOND * maxf(delta, 0.0))
	return not is_equal_approx(now, target)

func moving() -> bool:
	return not is_equal_approx(now, target)

## The drawn opacity (0..1), with the pointer's lift.
func shown(hovered: bool) -> float:
	return minf(now + (HOVER if hovered else 0), 255.0) / 255.0
