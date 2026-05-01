# 010-crt-postfx — plan

## Архитектура

### Узлы

```
CrtPostFx (autoload, CanvasLayer, layer = 128)
└── Screen (ColorRect, anchors_preset = full rect, mouse_filter = IGNORE)
    └── material = ShaderMaterial → crt.gdshader
```

`layer = 128` гарантирует, что мы поверх UiLayer'ов (обычно ≤10), DialoguePanel
и любых других CanvasLayer'ов. `mouse_filter = MOUSE_FILTER_IGNORE` —
чтоб ColorRect не съедал клики (без этого вся игра становится «накрытой
прозрачной плёнкой», и ни одна кнопка не нажимается).

### Файлы

| Путь | Назначение |
|---|---|
| `scripts/presentation/crt/crt_post_fx.gd` | autoload-скрипт CanvasLayer'а, F6-toggle, public api |
| `scripts/presentation/crt/crt.gdshader` | шейдер canvas_item с hint_screen_texture |
| `scenes/presentation/crt_post_fx.tscn` | сцена autoload'а (CanvasLayer + ColorRect) |
| `project.godot` | +1 autoload `CrtPostFx` в конец списка |

Папку `scenes/presentation/` создаём впервые — у проекта пока всё лежит плоско в
`scenes/ui/`, но `crt_post_fx` это не UI, и логичней вынести в отдельный путь,
чтоб не путать с реальными ui-сценами.

### Шейдер — структура

`shader_type canvas_item;` (читает то, что было нарисовано до этого CanvasLayer'а
через `hint_screen_texture`).

```glsl
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

uniform float curvature : hint_range(0.0, 0.5) = 0.08;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.35;
uniform float scanline_pitch_px = 3.0;   // привязка к ФИЗИЧЕСКИМ пикселям окна
                                          // (FRAGCOORD.y) — не муарит против
                                          // фактического размера viewport'а
uniform float aperture_strength : hint_range(0.0, 1.0) = 0.15;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.42;
uniform float chroma_strength : hint_range(0.0, 6.0) = 1.6;
uniform float warm_strength : hint_range(0.0, 1.0) = 0.28;
uniform float bloom_strength : hint_range(0.0, 1.5) = 0.55;
uniform float bezel_softness : hint_range(0.0, 0.2) = 0.04;
uniform float boost : hint_range(0.5, 2.5) = 1.35;
uniform vec3  warm_tint : source_color = vec3(1.18, 1.04, 0.78);   // янтарь
uniform vec3  phosphor_glow : source_color = vec3(0.030, 0.018, 0.008);
```

Pipeline на каждый фрагмент:
1. **uv → curved_uv**: barrel via `uv_centered + uv_centered * dot(uv_centered, uv_centered) * curvature`.
2. Если `curved_uv` вышло за `[0..1]` (за рамкой кинескопа) — выводим чёрный + bezel-soft-mask. `bezel_softness` даёт мягкую границу, не «зубчатую».
3. **chroma**: 3 сэмпла `screen_tex` со смещениями ±`chroma_strength * SCREEN_PIXEL_SIZE` для R и B каналов.
4. **bloom-ish**: 4-tap простой box-blur по соседним пикселям + добавляем со смешением `bloom_strength` к ярким (luma > 0.6) местам.
5. **scanline**: умножаем на `mix(1.0 - scanline_strength, 1.0, 0.5 + 0.5 * cos(FRAGCOORD.y * 2π / scanline_pitch_px))` —
   привязка к физическим пикселям окна, без муара.
6. **aperture mask**: домножаем на `vec3(1, 1-a, 1-a/2)` со сдвигом по `floor(SCREEN_UV.x * width / 3.0) % 3` (RGB-триплеты, хорошо видны при достаточно крупном пикселе).
7. **warm grade**: `color = mix(color, color * warm_tint, warm_strength)`, плюс лёгкое `pow(color, vec3(0.95))` чтоб тени стали тёплее.
8. **vignette**: `color *= 1.0 - vignette_strength * smoothstep(0.5, 1.4, length(uv_centered))`.

`TIME` использовать только если включён hum (выключено по умолчанию). Это
shader-анимация, не игровая логика — `GameSpeed` тут не при чём.

### Public API (`CrtPostFx`)

```gdscript
var enabled: bool         # вкл/выкл; setter переключает CanvasLayer.visible
func toggle() -> void     # вызывается по F6
func set_param(name: StringName, value: float) -> void  # для будущего settings-panel
```

Внутри `_unhandled_input` — слушаем `KEY_F6` (без echo, без зажатия) и зовём
`toggle()`. Паттерн скопирован из `scripts/infrastructure/game_speed.gd:48`.

### Альтернатива (отвергнута)

SubViewport-пайплайн: завернуть всю игру в `SubViewport`, сделать корневую
сцену `SubViewportContainer + TextureRect + Shader`. Преимущество — сканлайны
жёстко привязаны к игровым пикселям и не «дёргаются» при ресайзе окна.

Цена: переделать `main_menu.tscn` корнем, прокрутить координаты мыши через
`SubViewportContainer.stretch = true`, проверить все `Camera2D` (их в проекте
несколько по сценам arena), переделать loading_cover чтобы оставался поверх
пост-эффекта, а не под ним. Минимум полдня + риск сломать уже работающие
сцены. На джеме не окупается. Если после релиза доводить — это `011-crt-native`.

## Как это сочетается с существующим кодом

- `main_menu.tscn` и `arena/*` не трогаем.
- Текущие CanvasLayer'ы в `scenes/ui/`:
  - `toast_layer` 50, `run_summary` 60, `portal_transition` 60, `keybind_overlay` 70,
    `pause_menu` 80, `settings_panel` 90, `confirm_modal` 100 — все **под** нашим 128,
    получают CRT-эффект.
  - `loading_cover` 200 — **над** нашим 128, остаётся без сканлайнов. Это
    скорее плюс: переходы загрузки читаются чище, без визуального шума.
- `dialogue_panel` сейчас на CanvasLayer без явного layer (=0) → попадёт под
  CRT, как и нужно.
- `mouse_filter = MOUSE_FILTER_IGNORE` на нашем `Screen` ColorRect означает,
  что клики проходят сквозь и попадают на любой UI ниже по слоям.

## Порядок исполнения

См. `tasks.md`. Сначала шейдер на минимуме (curvature + scanlines + vignette),
проверяем что компилится и виден, потом наращиваем эффекты по одному, чтобы
каждый можно было откатить отдельным коммитом если что-то рассыпется.
