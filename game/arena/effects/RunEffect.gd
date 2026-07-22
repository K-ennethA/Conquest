extends AugmentEffect
class_name RunEffect

## A run-scoped augment effect: it changes the ArenaRun rather than a single unit -- an
## extra squad slot, a currency boon, or a wider draft. Applied once per run (via
## ArenaAugmentApplier.apply_run), not per unit. Only meaningful on Augments whose target
## is RUN.

## Extra squad capacity granted (informational until a mid-run recruit step reads it).
@export var extra_squad_slots: int = 0
## One-time currency added to the run.
@export var bonus_currency: int = 0
## Persistent bump to how many options future drafts offer (read by the draft roll).
@export var bonus_draft_options: int = 0


func apply_to_run(run) -> void:
	if run == null:
		return
	if bonus_currency != 0 and "currency" in run:
		run.currency += bonus_currency
	# extra_squad_slots / bonus_draft_options are stored on the run for the draft + recruit
	# systems to read; guarded so a run without the field simply ignores them.
	if extra_squad_slots != 0 and "bonus_squad_slots" in run:
		run.bonus_squad_slots += extra_squad_slots
	if bonus_draft_options != 0 and "bonus_draft_options" in run:
		run.bonus_draft_options += bonus_draft_options


func describe() -> String:
	var parts: PackedStringArray = []
	if bonus_currency != 0:
		parts.append("+%d gold" % bonus_currency)
	if extra_squad_slots != 0:
		parts.append("+%d squad slot" % extra_squad_slots)
	if bonus_draft_options != 0:
		parts.append("+%d draft option" % bonus_draft_options)
	return ", ".join(parts)
