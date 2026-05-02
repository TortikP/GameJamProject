# 025-feedback-polish — spec (RESERVED)

**Owner:** Andrey (driver, polish — его территория), все остальные точечно.
**Status:** Reserved — содержание заполняется утром, вне этой сессии.

## Цель (одно предложение)

Аудиовизуальный и интерфейсный фидбек на каждое действие игрока и AI — игрок всегда понимает, что произошло, что произойдёт, и что система услышала его ввод.

## Что входит (черновой каталог — фильтровать и приоритизировать утром)

### Pillar 1: «я вижу, что произойдёт» (телеграф)
- Усилить TelegraphHex: помимо damage-числа — иконка типа атаки (melee/ranged/AOE/heal/control), направление, длительность.
- Cast-range overlay чище: явная разница между «достижимо» и «out of range».
- Move-range overlay: показывать стоимость хода числом на гексе при cost>1.
- Aura-объекты (resolver 019 `aura_radius>0`) — постоянная пульсация на радиусе, не только при срабатывании.
- Linger-эффекты — overlay на гексе пока игрок там стоял, чтобы было видно, что эффект продолжится.

### Pillar 2: «я слышу/вижу, что произошло»
- SFX на каждое action: cast, hit, move-step, dodge, end-turn, button-press, modal-open, toast-appear.
- Floating numbers — улучшить читаемость (сейчас базовый pop, можно: цвет по типу, плавающий выше, подёргивание для крита).
- Hit-flash на актёрах (цвет по типу урона).
- Camera shake на серьёзных хитах (jam-scope: лёгкий, не утомляющий).
- Death animation manekin'ов — сейчас просто исчезают, нужен fall/dissolve.
- Tile-object destroy: VFX/SFX по `vfx_destroy`/`sfx_destroy` полям TileObject (поля есть, presentation не подключена — закрываем здесь).

### Pillar 3: «система меня слышит»
- Button hover/press animation (subtle scale, click-pulse).
- Slot-bar активный слот: better visual lock — сейчас цветовое отличие, добавить контурную обводку или lift.
- Keypress feedback для всех hotkey'ев (визуальный echo на ассоциированном UI элементе).
- Toast'ы — анимация slide-in/fade-out (сейчас instant).
- Modal'ы — fade-in вместо instant.
- **Hex-border preview style** (из 023 paint preview, `paint_preview.gd`) — переиспользовать стиль тонких FOCUS-окрашенных гекс-обводок для hover/highlight в боевом UI: ход курсора, выбранная ability area, валидные target hex'ы. Сейчас в бою используется монотонный fill — outline'ы читаются чище и не перекрывают тайлы.

### Pillar 4: pacing
- Step duration / cast wind-up — баланс через `GameSpeed`. Что слишком быстро? Что слишком медленно? Плейтест.
- AI thinking visible — небольшая пауза + индикатор «ход врага» в HUD до того, как враг начинает движение.

## Open questions (на утро)

- OQ-1: brand audio direction. Кто отвечает? Внешний free-asset pack? AI-generated через Suno? Никита?
- OQ-2: VFX набор — иконки/спрайты от Кати или Godot built-in particles?
- OQ-3: всё ли уложится в одну спеку, или придётся пилить на: 025-telegraph-pass / 025a-audio-pass / 025b-juice-pass? Вероятно да.
- OQ-4: какие из этих пунктов НЕ нужны для MVP-демо в субботу? Cut-list строить отсюда.

## Зависимости

- 022 (hex-shape) — стабилизация формы до телеграф-оверлеев.
- 023 (editor UX) — некоторые feedback-улучшения подойдут и для редактора (place-feedback, autosave-toast стайлинг).
- 024 (phase-bar) — wave-уведомления как часть feedback'а.

## Размер

Большая, ongoing. Скорее всего разделится на несколько P1 проходов и хвост из мелочей. Часть вещей логично делать вместе с фичей-источником, не отдельной волной.
