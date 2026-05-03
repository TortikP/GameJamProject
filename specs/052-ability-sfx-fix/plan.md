# 052 — Plan

## Touch list

```
NEW:
  default_bus_layout.tres                                       — Master/Music/SFX
  specs/052-ability-sfx-fix/{spec,plan,tasks}.md

EDIT:
  project.godot                                                 — +[audio] buses/default_bus_layout
  scripts/presentation/settings_panel.gd                        — apply slider values to buses on _ready

RENAME (git mv, both .wav and .wav.import + edit source_file= inside .import):
  assets/audio/sfx/abilitys/angel_divine_word_holy_heal_area/
    angel_divine_word_holy_heal_area_sond.wav
      → angel_divine_word_holy_heal_area_sound_start.wav
  assets/audio/sfx/abilitys/angel_scorching_ray_scorching/
    angel_scorching_ray_scorching_sound.wav
      → angel_scorching_ray_scorching_sound_start.wav
  assets/audio/sfx/abilitys/bear_paw_suck_self_heal/
    bear_paw_suck_self_heal_start_sound.wav
      → bear_paw_suck_self_heal_sound_start.wav
  assets/audio/sfx/abilitys/monkey_business_damage/
    monkey_business_damage_start_sound.wav
      → monkey_business_damage_sound_start.wav
  assets/audio/sfx/abilitys/mushroom_boar_spores_stun_area/
    mushroom_boar_spores_stun_area_sound start.wav
      → mushroom_boar_spores_stun_area_sound_start.wav
```

## default_bus_layout.tres

3 шины в фиксированном порядке: Master, Music, SFX. Music и SFX отправляют в Master. UID — свежесгенерённый. Громкости 0 dB, без mute/solo.

```
[gd_resource type="AudioBusLayout" format=3 uid="uid://b052audiobuslayoutv1"]

[resource]
bus/0/name              = &"Master"
bus/0/solo              = false
bus/0/mute              = false
bus/0/bypass_fx         = false
bus/0/volume_db         = 0.0
bus/0/send              = &""
bus/1/name              = &"Music"
bus/1/solo              = false
bus/1/mute              = false
bus/1/bypass_fx         = false
bus/1/volume_db         = 0.0
bus/1/send              = &"Master"
bus/2/name              = &"SFX"
bus/2/solo              = false
bus/2/mute              = false
bus/2/bypass_fx         = false
bus/2/volume_db         = 0.0
bus/2/send              = &"Master"
```

## project.godot diff

Вставить новую секцию `[audio]` между `[autoload]` и `[display]`:

```
[audio]

buses/default_bus_layout="res://default_bus_layout.tres"
```

После этого Godot грузит этот layout на старте AudioServer'а — до автолоадов. `MusicDirector._ready()` (`get_bus_index("Music") >= 0` → теперь true) и `AudioDirector._resolve_bus()` (теперь видит Music/SFX) автоматически переключаются на правильные шины без правок в коде директоров.

## settings_panel.gd diff

Сейчас value_changed у HSlider'а не фаерится при инициализации сцены — слайдеры показывают 0.6 для Music, но шина остаётся на 0 dB до первого касания. Фиксим вручную после `_resolve_bus_indices`:

```gdscript
func _ready() -> void:
    ...
    _resolve_bus_indices()
    _master_slider.value_changed.connect(_on_master_changed)
    ...
    # 052: apply current slider values to buses on startup so .tscn defaults
    # (e.g. Music=0.6) take effect without requiring user to touch the slider.
    _apply_initial_volumes()
    ...

func _apply_initial_volumes() -> void:
    _on_master_changed(_master_slider.value)
    _on_music_changed(_music_slider.value)
    _on_sfx_changed(_sfx_slider.value)
```

`_on_*_changed` уже обновляют label `%d%%` и пишут в шину через `_apply_bus_volume`, так что переиспользуем напрямую. Если шина не существует (`_*_idx == -1`), `_apply_bus_volume` сам сделает no-op.

## Rename mechanics

`git mv` обновит индекс. После rename'а нужно поправить `source_file=` внутри `.wav.import` — Godot использует это поле для проверки целостности импорта. Иначе на следующем открытии редактора Godot переимпортит и пересохранит сайдкар сам, но мы делаем это сейчас, чтобы коммит был чистым.

UID-ссылки сохраняются (`uid://...` в `.import` мы не трогаем) — никакие места, ссылающиеся на эти аудио по UID-у, не сломаются. На наш случай таких мест нет: резолвер 051 ходит по filesystem'у через `DirAccess` и грузит через `load(path)` — UID не используется.

## Notes

- Bus layout-файл по соглашению Godot 4 ищется по пути из `audio/buses/default_bus_layout` в project settings. Альтернативное имя `res://default_bus_layout.tres` без явной настройки тоже подхватывается, но мы пишем явно — детерминированно и видно при чтении project.godot.
- `_apply_bus_volume(idx, value)` уже корректно обрабатывает граничные случаи: `value <= 0.0001` → mute; иначе `linear_to_db(value)`. Никаких дополнительных guard'ов на старте не нужно.
- После пуша Egor открывает Godot — он переимпортит 5 переименованных wav'ов автоматически, обновит хеш в `path=` внутри `.import` и сложит новый `.sample` в `.godot/imported/`. Это не часть коммита, это локально у каждого.
