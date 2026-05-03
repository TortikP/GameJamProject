class_name StunnedRuntime
extends StatusRuntime
## stunned — носитель не совершает действий и не передвигается.
## Реализация — вне runtime: AI planner и HUD читают actor.is_stunned()
## и пропускают планирование / блокируют ввод. Runtime — pure marker.
## 027: spec §"Контракт статусов" / AC-RT-stunned.
##
## ⚠ DURATION SEMANTICS (off-by-one): tick happens at world_turn_ended,
## BEFORE the affected actor's next action. So `stunned(N)` skips (N-1)
## actor turns:
##   stunned(1) → 0 skips (no-op — never write this)
##   stunned(2) → 1 skip
##   stunned(3) → 2 skips
## Same applies to all duration-based statuses (slowed, weakened, burning),
## but stunned is the most visibly broken at N=1 because it's all-or-nothing.
## When designing skills, write N = (desired_skips + 1).
