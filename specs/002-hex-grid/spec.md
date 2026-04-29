# 002-hex-grid — spec

**Owner:** Egor
**Status:** draft

## Цель

Игровое поле для боёв: гексагональная сетка с типизированной местностью, тайл-эффектами, отслеживанием позиций акторов и навигацией мышь+клавиатура. Один источник правды о том, кто где стоит и что под ним. Бой/враги/спеллы — снаружи, через EventBus.

## Acceptance criteria

- 10×10 гекс-сетка отрисована, видна целиком на 1280×720, центрирована.
- Местность: ≥3 типа (passable / blocked / difficult). Тип читается из `TileData.get_custom_data(...)`, не из «какого слоя тайл».
- Тайл-эффекты: ≥2 типа (`damage_zone`, `heal_zone` как примеры). Срабатывают через сигнал EventBus при входе актёра, а не внутри HexGrid.
- Static-эффекты — частью карты (custom data); dynamic-эффекты — runtime overlay, спавнятся/удаляются программно.
- API позиций акторов: `place_actor / move_actor / get_coord / get_actor_at / clear_actor`. На один coord — максимум один актёр.
- Курсор: `coord_under_mouse() -> Vector2i` (`Vector2i(-1,-1)` = вне сетки). Подсветка тайла под курсором.
- Клик ЛКМ по достижимому тайлу → актёр идёт по найденному пути (учёт blocked + difficult cost).
- Клавиатурное движение: 6 направлений (полный набор соседей), не 4. Конкретная схема — в `plan.md` §4 + input actions в `project.godot`.
- Pathfinding: `AStar2D`, перестраивается на изменения проходимости.
- EventBus получает: `actor_moved(id, from, to)`, `tile_entered(id, coord)`, `tile_effect_triggered(id, coord, effect_id)`. HexGrid не знает про HP, ману, AI — только эмитит.
- Все тайминги шага актёра — через `GameSpeed.wait("arena", ...)`. Хардкоженных `create_timer` нет.
- Demo-сцена `scenes/arena/hex_grid_demo.tscn` запускается изолированно и демонстрирует всё перечисленное с placeholder-тайлами Кати или плоскими цветами.

## Out of scope

- Реальный арт от Кати (placeholders 64×64 заливками — ок).
- Туман войны / line-of-sight / видимость.
- 3D или многоуровневые арены.
- AI врагов, бой, HP/мана, спеллы — потребители событий, не часть фичи.
- Сетевая синхронизация.
- Мини-карта, scroll/zoom камеры (камера статична на demo).
- Поворот гекс-ориентации в рантайме.
- Динамическое изменение размера сетки в рантайме.

## Acceptance verification

Запуск `scenes/arena/hex_grid_demo.tscn`:
1. Видна 10×10 сетка с тремя типами тайлов (визуально различимыми).
2. Тестовый актёр (цветной круг) на стартовом гексе.
3. Подсветка под курсором следует за мышью; за пределами сетки гаснет.
4. Клик по проходимому → актёр шагает по пути; клик по blocked → лог `[INFO][HexGrid] unreachable`; клик по difficult → проходит, но шаги медленнее (по `move_cost`).
5. Q/W/E/A/S/D (или выбранная схема из plan §4) → шаг в соответствующего соседа; в blocked не шагает.
6. Войти на damage_zone → в логах `[INFO][HexGrid] tile_effect_triggered: damage_zone @ (x,y) for player`.
7. F5 hot-reload `game_speed.cfg` меняет скорость шага без рестарта.

## Зависимости

- 001-bootstrap (autoloads + структура) — должен быть смерджен в staging.
- EventBus получает 3 новых сигнала (additive, не breaking).
- `config/game_speed.cfg` получает секцию `[arena]`.

## Open questions перед стартом implement

- **Ориентация гекса** (flat-top vs pointy-top) — рекомендация в plan §1, финальное слово за Егором при сборке TileSet.
- **6-key схема** — рекомендация в plan §4, корректируется по ходу плейтеста.
- **Effect resolution** sync vs async (await before next move?) — по умолчанию sync, актёр стоит на тайле пока эффект не отработает; обсуждаемо.
