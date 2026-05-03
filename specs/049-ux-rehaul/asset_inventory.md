# Asset inventory — icons needed for 049

For Katya. 16×16 or 24×24 PNG, alpha channel; drop into the matching
folder and the existing letter-fallback resolves to texture automatically.

## Status effects → `assets/icons/statuses/<id>.png`

12 in production:

| id | family | letter fallback |
|---|---|---|
| burning  | dot     | B |
| enraged  | debuff  | E |
| feared   | control | F |
| glitched | debuff  | G |
| poisoned | dot     | P |
| rooted   | control | R |
| shielded | shield  | S |
| slowed   | debuff  | S |
| strong   | buff    | S |
| stunned  | control | S |
| summoned | neutral | S |
| weak     | debuff  | W |

Note four S-letter collisions (shielded/slowed/strong/stunned) — icons
matter most for these.

## Skills → `assets/icons/skills/<id>.png`

51 in production (test_* skipped):

angel_divine_word, angel_scorching_ray, angel_sharp_feathers,
ball_throw, bear_ball_throw, bear_hallo, bear_paw_suck, bee_honey_cold,
bee_sting, bee_summon_bee, berry_throw, burning_bear_burning_claw,
burning_bear_hellshake, burning_bear_summon_bear, burning_bear_tire_throw,
bush_berry_throw, bush_curse, bush_nice_smell, curse, default_heal,
default_melee, default_ranged, fire_slime_firey_touch, fire_slime_magma_spit,
hallo, honey_cold, lavender_lion_bite, lavender_lion_roar, lavender_lion_scare,
monkey_business, monkey_time, mushroom_boar_spores, mushroom_boar_tusk_attack,
mushroom_boar_weaken, nice_smell, paper_jam, paw_suck, spores, staple_shot,
stapler_paper_jam, stapler_staple_shot, stapler_under_desk_jump, sting,
summon_bee, teapot_low_possibility, teapot_spill_the_t, teapot_tea_gathering,
tusk_attack, under_desk_jump, weaken

Drop `<id>.png` into the folder; SkillIconResolver picks it up by path
pattern `icons/skills/<id>.png` automatically. No code changes needed
once assets land — TelegraphHex / HexTooltip / EnemyDetailsPanel /
SkillOfferCard all share the same resolver.
