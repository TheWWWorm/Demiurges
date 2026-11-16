extends "res://../tools/duel_rules_check.gd"
## How much of each game's duel rules the compiled engine's model holds.
##
## Every card with a rule, every creature, every enchantment that can stand
## on a creature or a hero and every thing a hero may carry is tried on its
## own in a few small positions: whatever the engine lists for it there is
## played through the game's rules and through the model's, alone and
## followed by three turn ends, and the two must leave the same board, hands,
## graveyards, ether and health. One line is printed for each:
##
##   COVER <kind> <name> <status> lines=.. agree=.. differ=.. chance=.. unlisted=.. incomplete=.. reasons=.. | notes
##
## kind: card (cast from the hand), creature (in play: fights, abilities,
## turns), worn (an enchantment on a creature), laid (one on a hero),
## carried (a thing a hero carries). status: agrees, differs, chance (the
## game drew on chance the model is not told), unlisted (the game allows a
## use the engine does not list), incomplete (the model went past what it has
## room for), unexercised (nothing could be done with it in the positions).
## COVERED lines total the statuses by kind. The heroes' specialisations are
## held by the fixtures of tools/duel_rules_check.gd --parity=1.
##
##   godot --headless --path game --script ../tools/duel_model_coverage.gd -- --game=el1 [--shard=k/n] [--kinds=card,creature,worn,laid,carried] [--names=A,B]

func _init() -> void:
	coverage_only = true
