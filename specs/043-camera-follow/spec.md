# 043-camera-follow — spec

**Owner:** Andrey
**Status:** Draft → impl в этой же ветке.

## Контекст

`scripts/presentation/godmode/godmode_camera.gd` — общий Camera2D-скрипт
для godmode (бой) и map_editor. Текущее поведение одинаковое:
MMB-pan, wheel-zoom, центрирование на target один раз при `_ready` и при
`set_follow_target`. После начального центрирования в бою камера **остаётся
неподвижной** — игрок ходит по гексам и при достаточно большой арене уезжает
за пределы экрана. В редакторе drag нужен (двигаем рабочую область),
в бою — нет (мешает следящей камере и сбивает читаемость).

## Цель

В бою камера всегда держит игрока в центре с лёгким smoothing'ом (Camera2D
встроенный). MMB-drag в бою отключён. В map_editor поведение неизменно:
drag + wheel-zoom + zoom-to-cursor.

## Acceptance criteria

- **AC-1 (follow в бою).** В godmode-сцене камера каждый кадр позиционируется
  на `_follow_target.global_position`, пока target жив. Игрок видим в центре
  экрана независимо от его перемещения по гексам.
- **AC-2 (drag в бою отключён).** В godmode MMB-drag не двигает камеру.
  Событие игнорируется без побочных эффектов; `_panning` не выставляется.
- **AC-3 (zoom везде сохранён).** Mouse-wheel zoom работает в обеих сценах.
  В godmode (follow-mode) zoom — чисто scale без cursor-anchored смещения
  (всё равно затёрло бы `_process`'ом). В map_editor zoom-to-cursor работает
  как раньше.
- **AC-4 (drag в редакторе сохранён).** В map_editor MMB-drag двигает
  камеру как раньше; никаких изменений в этой сцене.
- **AC-5 (минимизация diff).** Правки только в
  `scripts/presentation/godmode/godmode_camera.gd` и
  `scenes/dev/godmode.tscn`. Никаких новых файлов, autoload'ов, классов,
  GameSpeed-ключей.
- **AC-6 (graceful target loss).** Если `_follow_target` становится `null` /
  `!is_instance_valid` — камера остаётся на последней позиции, free-mode
  переключается обратно (drag снова работает), не крашится.
- **AC-7 (smoothing).** `position_smoothing_enabled = true` на ноде в
  godmode.tscn, скорость по дефолту Godot (5.0). Плавное следование без
  телепорта при переходе между гексами.

## Дизайн-решение: mode-by-presence

Mode не вводится как отдельный enum / setter. Вместо этого:
**наличие `_follow_target != null && is_instance_valid(_follow_target)`
⇒ camera в follow-mode**. map_editor никогда не вызывает `set_follow_target`,
поэтому остаётся в free-mode. `godmode_setup.gd` уже вызывает
`set_follow_target(player)` при спавне игрока и при load custom level —
автоматом включает follow-mode. Минимум API-поверхности, минимум touch
points, нулевая интеграция со стороны вызывающего кода.

## Out of scope

- Bounds-clamping (запрет уезжать за края арены) — отдельный спек, не нужен
  пока в бою камера всегда на игроке.
- Camera shake / impact-эффекты — отдельный спек, polish.
- Edge-pan / следование с offset под UI — пока вся арена ≤ экрана при
  дефолтном zoom, не нужно.
- Любое изменение поведения в map_editor — там работало, там и останется.
- Изменения других сцен (`main_menu`, `ui_lab`, music_lab, etc.) — они не
  используют `godmode_camera.gd`.
- Зум во время follow с zoom-to-cursor (сложно совместить со snap'ом, не
  критично — зум в бою чаще "просто хочу шире/уже").

## Risks

- **Конфликт `_process` follow-loop и `position_smoothing`.** Camera2D
  при `position_smoothing_enabled` интерполирует **отрисовываемый** anchor
  к текущему `position`. Установка `global_position` каждый кадр на target —
  ровно то, к чему smoothing должен интерполировать. Конфликта нет, но
  если визуально дёргается — отключаем smoothing (zero-cost rollback).
- **AI / level-transition пересоздаёт player'а.** `godmode_setup` уже зовёт
  `set_follow_target` повторно при load custom level. Старый ref становится
  invalid → `_process` гард `is_instance_valid` ловит → один кадр без
  follow → следующий вызов set_follow_target обновляет ref. Без crash'а.

## Success

- В godmode: ходишь стрелками / по гексам — игрок остаётся в центре экрана,
  колесо мыши зумит без артефактов, MMB не двигает камеру.
- В map_editor: всё как было.
- Diff ≤ 30 строк кода + 1 строка в .tscn.
