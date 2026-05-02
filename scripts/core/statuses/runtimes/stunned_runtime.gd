class_name StunnedRuntime
extends StatusRuntime
## stunned — носитель не совершает действий и не передвигается.
## Реализация — вне runtime: AI planner и HUD читают actor.is_stunned()
## и пропускают планирование / блокируют ввод. Runtime — pure marker.
## 027: spec §"Контракт статусов" / AC-RT-stunned.
