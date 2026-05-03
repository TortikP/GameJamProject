# 050-sprite-fit-tile-width — spec

**Owner:** Andrey (UX/integration polish).
**Status:** Draft → ready to land (две независимые правки, низкий риск).

## Revision 3 (post-review)

1. **Player scale возвращён.** `scenes/dev/player.tscn` Body — `scale = Vector2(1.5, 1.5)` восстановлен. Игрок снова рендерится в 1.5× нативного размера player.png. (Native 32×50 → displayed 48×75.)
2. **Manekin sprite-зависимость удалена.** SpawnerPlaceholder больше не содержит хардкоженного списка `ENEMY_SPRITES` со ссылкой на `manekin.png`. Текстура подгружается динамически по `spawner_ref` через новый static helper `EnemyDataLoader.get_sprite_path(enemy_id)`. Преимущества:
   - Любой новый enemy в `data/enemies/*.json` автоматически работает в spawner placeholder без правок кода.
   - `assets/sprites/manekin.png` больше не preload'ится (был импортирован при старте игры просто из-за hardcoded словаря).
   - `scenes/runtime/spawner_placeholder.tscn` больше не имеет ext_resource на manekin.png (убран и default `texture` на Sprite, и `modulate` baked-value — оба перезаписываются скриптом).
3. **Darkening через modulate.** Раньше: `Color(1.0, 1.0, 1.0, 0.45)` (полупрозрачный, full-bright). Теперь: `SHADOW_TINT = Color(0.3, 0.3, 0.3, 0.85)` — RGB опущены до 30% (тёмная силуэт-версия), alpha 85% (почти solid). Constant вынесен наверх скрипта для будущего тюнинга.

**Что НЕ затронуто:**
- `data/enemies/manekin.json` (manekin как enemy_id всё ещё валиден, используется в `data/maps/*.json` и AI behavior сценариях; убрать его — отдельный широкий рефактор за рамками этого спека).
- `assets/sprites/manekin.png` и `assets/sprites/enemies/manekin.png` — оба остаются на диске (последний всё ещё ссылается из `data/enemies/manekin.json`).
- Docstring example в `enemy_data_loader.gd` упоминает manekin как пример schema — это документация, не зависимость.

---



Полный откат sprite-fit. ObjectsOverlay тоже больше не fit'ит — все спрайты (player, enemies, tile-objects, spawner placeholder) рендерятся в нативных размерах. Конкретные правки:

1. `scenes/dev/player.tscn` — убран `scale = Vector2(1.5, 1.5)` у Body. Игрок рендерится 32×50 (native player.png).
2. `scenes/runtime/spawner_placeholder.tscn` — убран `scale = Vector2(0.09, 0.09)` у Sprite. **Известное следствие:** пока в `ENEMY_SPRITES` dict у `spawner_placeholder.gd` ссылка на manekin.png (664×788) — placeholder будет визуально гигантским. Решается заменой ассета (Катя).
3. `scripts/presentation/dev/objects_overlay.gd` — откачен SpriteFit, восстановлен `sprite.scale = Vector2(sprite_scale, sprite_scale)` (export var, default 1.0 → native size). Helper `_tile_width()` удалён.
4. `scripts/infrastructure/sprite_fit.gd` — удалён (нет consumers).

Что остаётся в спеке после revision 2:
- DialoguePanel Portrait widget (`130×180`, `expand_mode=0`, `stretch_mode=2`, `clip_contents=true`, `size_flags_vertical=4`).
- `_make_placeholder` rewrite на `default_portrait.png` fallback.
- Импорт 14 ассетов от Кати.

Sprite-fit подсистема отменена целиком. Если позже понадобится возврат — `git revert` коммитов 78e01c7 (feat) и 66a074c (rev1) даст оригинальное состояние; новый подход будет жить в отдельном спеке.

---



После ревью на первой версии:
1. **Actor sprite-fit откачен.** Player Body → возврат к `scale=Vector2(1.5,1.5)` в .tscn. EnemyView → SpriteFit вызов удалён, спрайты enemies снова рендерятся в нативных размерах (≠ 128). SpawnerPlaceholder → возврат к `scale=Vector2(0.09,0.09)` для маникена. Файл `scripts/presentation/godmode/player_view.gd` удалён. Tile-objects fit — **остаётся** (отдельная подсистема, не actors).
2. **Dialogue Portrait** теперь конфигурируется per скриншот ревью: `expand_mode=0` (Keep Size), `stretch_mode=2` (Keep) вместо изначальных `1`/`6`. Добавлены `clip_contents=true` и `size_flags_vertical=4` (Shrink Center). Семантика: текстура рендерится pixel-perfect 1:1, центрирована вертикально внутри 130×180 слота, клиппинг защищает от overflow при будущих larger портретах.
3. **Новые ассеты импортированы** (партия от Кати, 14 файлов):
   - `aspect_fire.png` / `aspect_forest.png` / `aspect_heaven.png` (130×180) → `assets/portraits/`
   - `enemy_boar.png` / `enemy_slime.png` / `enemy_stepler.png` / `enemy_teapot.png` → `assets/sprites/enemies/` (префикс `enemy_` сброшен per Andrey, teapot.png — overwrite)
   - `object_heal.PNG` / `object_lava.png` / `tile_heaven_{1,2,3}.png` / `tile_lava_{1,2}.png` → `assets/tiles/` (object_lava.png — overwrite)

Sprite-fit код (`SpriteFit` utility) сохранён, используется только в ObjectsOverlay.

---

## Цель

Две косметические правки, бандлятся в один спек потому что обе про размеры презентации и обе тривиальные:

1. **Спрайты актёров и tile-objects масштабируются под ширину гекса** (128 px) с сохранением соотношения сторон. Сейчас спрайты в репе разного нативного размера (player.png 32×50, manekin.png 664×788, bear.png 80×80, fire_slime.png 151×153 итд) и каждый рендерится со своим хардкоженным `scale` в .tscn — выглядит как "кто во что горазд": игрок 48×75, маникен почти 800px на 128-pixel hex, и т.д. Унифицируем: каждый Body Sprite2D скейлится так что итоговая ширина = ширина тайла (128). Высота — пропорционально, спрайт может выходить за вертикальные границы тайла (это нормально, персонажи стоят на тайле, а не вписываются в него).

2. **Левая картинка в DialoguePanel меняет соотношение сторон с 1:1 на 13:18** и получает дефолтный плейсхолдер. Сейчас Portrait — TextureRect 160×160 (квадрат), а когда спрайт не задан — рендерится flat colored rect через `_make_placeholder`. Меняем на 130×180 (= 13:18) и кладём дефолтную картинку `assets/portraits/default_portrait.png` (приложенный `acpest.png`), которая используется как fallback вместо flat rect.

## Scope-граница

**В скоупе:**
- Новый утилитарный модуль `scripts/infrastructure/sprite_fit.gd` со static-функцией `fit_to_tile_width(sprite, tile_width=128, base_scale=1.0)`.
- Применение fitter'а в 4 местах рендера: `player_view.gd` (новый, заменяет прямой `actor.gd` на player.tscn), `enemy_view.gd`, `objects_overlay.gd`, `spawner_placeholder.gd`.
- Удаление хардкоженных `scale=Vector2(...)` в .tscn (player, enemy, spawner_placeholder) — fitter перезаписывает.
- DialoguePanel: Portrait `custom_minimum_size = Vector2(130, 180)`, `_make_placeholder` пробует загрузить `assets/portraits/default_portrait.png` перед fallback'ом на flat rect.
- Новый ассет `assets/portraits/default_portrait.png` + `.png.import` sidecar.

**Вне скоупа:**
- Per-actor оффсеты позиции / vertical alignment (player.tscn оставляет `position = Vector2(0, -5)` как было, enemies и tile-objects свои оффсеты не меняют). Если кому-то после fitter'а спрайт визуально "слишком высоко/низко" — это per-actor tweak в .tscn / в overlay-конфиге, отдельный спек.
- Изменение тайла (128 px hardcoded). CLAUDE.md hard rule #7 фиксирует tile_size — не трогаем.
- Per-speaker дефолтные портреты в `_speakers.json`. Меняется только глобальный fallback в `_make_placeholder`. Если у speaker'а валидный `default_portrait` путь и файл существует — он по-прежнему имеет приоритет.
- Размер DialoguePanel в целом / margins / шрифты. Только Portrait min-size.
- Применение fitter'а к VFX-спрайтам (fx_director.gd, corpse.gd) — у них собственная логика scale (corpse читает `actor.scale * body.scale` → автоматически наследует исправленный scale; fx — независимая система).

## Что вводится

### 1. `scripts/infrastructure/sprite_fit.gd`

Stateless utility. Static-only, без `class_name` (per CLAUDE traps таблица — `class_name` для утилит ловит коллизии). Consumers делают `const SpriteFit = preload("res://scripts/infrastructure/sprite_fit.gd")`.

```gdscript
extends Object

const TILE_WIDTH_DEFAULT := 128

# Sets sprite.scale so the sprite's displayed width == tile_width * base_scale,
# preserving aspect ratio. No-op on null sprite, null texture, or zero-width texture
# (logs warn). base_scale lets callers stack a multiplier (e.g. ObjectsOverlay
# keeps its export var sprite_scale as a per-overlay tuning knob).
static func fit_to_tile_width(sprite: Sprite2D, tile_width: int = TILE_WIDTH_DEFAULT, base_scale: float = 1.0) -> void
```

### 2. `scripts/presentation/godmode/player_view.gd`

Mirror of `enemy_view.gd` для игрока. Тонкий subclass:

```gdscript
extends Actor

const SpriteFit = preload("res://scripts/infrastructure/sprite_fit.gd")

func _ready() -> void:
    var body := get_node_or_null("Body") as Sprite2D
    if body != null:
        SpriteFit.fit_to_tile_width(body)
    super._ready()
```

Заменяет `actor.gd` на root'е `scenes/dev/player.tscn`. Контракт `Actor` сохраняется (Player всё ещё `as Actor` для всех consumer'ов — `LevelLoader._spawn_player`, `godmode_setup`).

### 3. Изменения в существующих файлах

- `scripts/presentation/godmode/enemy_view.gd`: после `body.texture = tex` (~line 37) — `SpriteFit.fit_to_tile_width(body)`.
- `scripts/presentation/dev/objects_overlay.gd`: в `set_object()` после `sprite.texture = tex` — `SpriteFit.fit_to_tile_width(sprite, _tile_width(), sprite_scale)`. Tile width читается из `grid.tile_map_layer.tile_set.tile_size.x` если grid есть, иначе fallback 128.
- `scripts/presentation/runtime/spawner_placeholder.gd`: в `_apply_visuals()` после `_sprite.texture = ...` — `SpriteFit.fit_to_tile_width(_sprite)`. Это **перезаписывает** `scale = Vector2(0.09, 0.09)` из .tscn — поэтому из .tscn хардкод убираем.
- `scenes/dev/player.tscn`: root script меняется на `player_view.gd`. У Body убирается `scale = Vector2(1.5, 1.5)`. `position = Vector2(0, -5)` остаётся.
- `scenes/dev/enemy.tscn`: у Body убирается `scale = Vector2(1, 1)` (no-op tweak, было дефолтом — но удаляем явное дублирование, чтобы fitter был единственным источником scale).
- `scenes/runtime/spawner_placeholder.tscn`: у Sprite убирается `scale = Vector2(0.09, 0.09)`.
- `scenes/ui/dialogue_panel.tscn`: Portrait `custom_minimum_size = Vector2(130, 180)`.
- `scripts/presentation/dialogue_panel.gd._make_placeholder()`: пробует `load("res://assets/portraits/default_portrait.png")` → если успешно, кэширует и возвращает. Иначе старый fallback (flat rect, но размер обновляется до 130×180 для консистентности).

### 4. Новые ассеты

- `assets/portraits/default_portrait.png` — копия `acpest.png` (130×180, RGBA8).
- `assets/portraits/default_portrait.png.import` — sidecar по шаблону `bush.png.import`. UID свежий. Godot перегенерит cached `.ctex` на первом открытии редактора — это нормально, .import коммитим, .ctex (внутри `.godot/`) gitignore'ится.

## Acceptance criteria

- **AC-1.** Игрок появляется на тайле, его Body Sprite2D имеет `scale.x == scale.y` и displayed width ≈ 128 px (с погрешностью ±1 px на округление).
- **AC-2.** Любой spawned enemy через `enemy_view.gd` (manekin, bear, angel, bee, fire_slime, mushroom_boar, monkey, lavender_lion, burning_bear, bush) — displayed width ≈ 128 px независимо от нативного размера спрайта в `assets/sprites/enemies/`.
- **AC-3.** В map editor / godmode tile-object (например `tree`, `mountain`, `crystal`) с реальным `sprite_path` рендерится с displayed width ≈ 128 px. Если `sprite_path` пустой — fallback silhouette не меняется (силуэт сам себе размер задаёт).
- **AC-4.** SpawnerPlaceholder перед волной: маникен-призрак ≈ 128 px широкий, не 60.
- **AC-5.** DialoguePanel Portrait слот — 130 px wide × 180 px tall (= 13:18). Когда никакого портрета не задано (line.portrait="" и speaker.default_portrait не существует на диске) — отображается `default_portrait.png` (приложенный `acpest.png`).
- **AC-6.** Если у speaker'а валидный `default_portrait` файл — приоритет за ним, дефолтный плейсхолдер не используется.
- **AC-7.** Изменение `sprite_path` в JSON tile-object на отсутствующий файл → silhouette fallback не падает (без NPE), как было.
- **AC-8.** Sprite c null texture (теоретически возможно если data malformed) — fitter не падает, sprite остаётся со scale что был.

## Out of scope, тестирование

- Автотесты не пишем (jam, нет тестового ранера). Smoke-тесты на разработчике: spawn маникена в godmode, открыть map editor с tree/mountain, запустить волну, открыть intro dialogue.
- Если после fitter'а где-то спрайт читается визуально слишком высоко (выходит из тайла на пол-арены вверх) — это per-actor оффсет, отдельный тюнинг.

## Риски

- **R1.** Player.tscn root script change ломает что-то ожидающее точно `Actor` script (не subclass). Митигация: subclass `extends Actor`, все консьюмеры кастят `as Actor` — работает с subclass.
- **R2.** Маникен в spawner_placeholder становится крупнее (с ~60 wide до 128) — может перекрывать соседние UI элементы (label с countdown). Митигация: label позиция в .tscn (`offset_top = -64`) сейчас рассчитан под старый размер. После fitter'а маникен 128×151 — label на y=-64 всё ещё над спрайтом (центр спрайта в (0,0), верх на y=-75). Должно быть ок, но проверить smoke.
- **R3.** `default_portrait.png.import` без свежего Godot-импорта может не открыться в редакторе. Митигация: формат .import — текстовый INI с placeholder uid, Godot перегенерирует cached `.ctex` автоматически на первом открытии. Проверено по pattern существующих .import файлов в репе.
