#!/usr/bin/env python3
"""Compose Polyabsorb sprite-showcase sheets for presentations / pitch decks.

Generates 5 PNGs in <repo>/sprite_sheets/ (gitignored):
  01_characters.png    — портреты + игрок + враги (real size, no manekin)
  02_skill_icons.png   — иконки умений
  03_tiles_atlases.png — гекс-атлас, варианты гексов, объекты на тайлах
  04_skills.png        — каталог умений с описаниями (берёт RU из data/localization)
  05_features.png      — обзор функционала игры

Palette: Win98-teal, mirrored from scripts/presentation/ui_theme.gd (spec 047).
Fonts: DejaVuSans (TrueType bundled on most Linux installs).

Run from repo root or anywhere — script auto-detects repo path:
    python3 scripts/tools/build_sprite_sheets.py

Dependency: Pillow (pip install Pillow).
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import json
import math

# ── Repo-relative paths (script is at <repo>/scripts/tools/) ─────────
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'sprite_sheets'
OUT.mkdir(parents=True, exist_ok=True)

FONT_BOLD    = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
FONT_REG     = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FONT_OBLIQUE = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf'

# ── Win98-teal palette (mirrors UiTheme constants) ──────────────────
# UiTheme.BG_SCREEN #001a1d (slight tint variation for vertical gradient)
BG_TOP    = (0, 28, 32)
BG_BOTTOM = (0, 10, 14)
# UiTheme.BORDER_STRONG #00c8c8 — primary accent
ACCENT    = (0, 200, 200)
# UiTheme.BORDER #008080 — Win98 desktop teal
ACCENT_DIM= (0, 128, 128)
# UiTheme.TEXT #d8f0f0
LABEL     = (216, 240, 240)
# UiTheme.TEXT_DIM #88b0b0
LABEL_DIM = (136, 176, 176)
# UiTheme.TEXT_FAINT #4a7070
LABEL_VDIM= (90, 130, 130)
# UiTheme.BG_PANEL #002830
CELL_BG   = (0, 40, 48)
# UiTheme.BG_ELEVATED #004d59
CELL_EDGE = (0, 90, 105)

RU = json.loads((ROOT / 'data/localization/ru.json').read_text())


def font(size, bold=True, italic=False):
    if italic:
        return ImageFont.truetype(FONT_OBLIQUE, size)
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)


def gradient_bg(size):
    w, h = size
    img = Image.new('RGB', size, BG_TOP)
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(BG_TOP[0] * (1 - t) + BG_BOTTOM[0] * t)
        g = int(BG_TOP[1] * (1 - t) + BG_BOTTOM[1] * t)
        b = int(BG_TOP[2] * (1 - t) + BG_BOTTOM[2] * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return img


def text_w(draw, txt, fnt):
    bbox = draw.textbbox((0, 0), txt, font=fnt)
    return bbox[2] - bbox[0]


def text_h(draw, txt, fnt):
    bbox = draw.textbbox((0, 0), txt, font=fnt)
    return bbox[3] - bbox[1]


def header(draw, w, top, subtitle):
    """Draw 'POLYABSORB' + subtitle + divider. Returns y below the divider."""
    title_fnt = font(52, bold=True)
    sub_fnt = font(20, bold=False)
    title = 'POLYABSORB'
    tw = text_w(draw, title, title_fnt)
    sw = text_w(draw, subtitle, sub_fnt)
    draw.text(((w - tw) // 2, top), title, fill=ACCENT, font=title_fnt)
    draw.text(((w - sw) // 2, top + 64), subtitle, fill=LABEL_DIM, font=sub_fnt)
    line_y = top + 102
    draw.line([(w * 0.18, line_y), (w * 0.82, line_y)], fill=ACCENT_DIM, width=1)
    return line_y + 30


def section_label(draw, text, w, y):
    fnt = font(20, bold=True)
    tw = text_w(draw, text, fnt)
    draw.text(((w - tw) // 2, y), text, fill=ACCENT_DIM, font=fnt)
    return y + 34


def caption_line(draw, text, w, y, italic=False):
    fnt = font(14, bold=False, italic=italic)
    tw = text_w(draw, text, fnt)
    draw.text(((w - tw) // 2, y), text, fill=LABEL_DIM, font=fnt)
    return y + text_h(draw, text, fnt) + 6


def _draw_label(canvas, draw, label, x, y, w, label_h, font_size, color=LABEL):
    fnt = font(font_size, bold=True)
    bbox = draw.textbbox((0, 0), label, font=fnt)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    while tw > w - 16 and len(label) > 3:
        label = label[:-1]
        bbox = draw.textbbox((0, 0), label + '…', font=fnt)
        tw = bbox[2] - bbox[0]
    y_off = (label_h - th) // 2 - bbox[1]
    draw.text((x + (w - tw) // 2, y + y_off), label, fill=color, font=fnt)


def draw_realsize_cell(canvas, x, y, cell_w, cell_h,
                       sprite_path, label,
                       sprite_max_w, sprite_max_h,
                       sprite_pad_top=10, label_h=32, font_size=15):
    """Sprite at NATIVE pixel size, bottom-aligned. Downscaled if oversized."""
    cell = Image.new('RGBA', (cell_w, cell_h), (0, 0, 0, 0))
    cdraw = ImageDraw.Draw(cell)
    cdraw.rounded_rectangle((0, 0, cell_w - 1, cell_h - 1), radius=8,
                            fill=CELL_BG + (200,),
                            outline=CELL_EDGE + (255,), width=1)
    try:
        im = Image.open(sprite_path).convert('RGBA')
    except Exception:
        cdraw.text((10, 10), f'?? {sprite_path.name}', fill=(255, 100, 100), font=font(10))
        canvas.paste(cell, (x, y), cell)
        return
    if im.width > sprite_max_w or im.height > sprite_max_h:
        scale = min(sprite_max_w / im.width, sprite_max_h / im.height)
        im = im.resize((max(1, int(im.width * scale)),
                        max(1, int(im.height * scale))), Image.LANCZOS)
    sprite_area_h = cell_h - label_h - sprite_pad_top
    sx = (cell_w - im.width) // 2
    sy = sprite_pad_top + (sprite_area_h - im.height)
    cell.paste(im, (sx, sy), im)
    _draw_label(cell, cdraw, label, 0, cell_h - label_h, cell_w, label_h, font_size)
    canvas.paste(cell, (x, y), cell)


def label_for_enemy(stem):
    return RU.get(f'{stem}_name', stem.replace('_', ' ').title())


def wrap_text(draw, text, fnt, max_w):
    if not text:
        return []
    words = text.split()
    lines = []
    cur = ''
    for w in words:
        test = (cur + ' ' + w).strip()
        if text_w(draw, test, fnt) <= max_w:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


BOTTOM_PAD = 30


# ============================================================
# SHEET 1 — Characters & portraits
# ============================================================
def sheet_characters():
    portraits = [
        (ROOT / 'assets/portraits/default_portrait.png',  'По умолчанию'),
        (ROOT / 'assets/portraits/aspect_fire.png',       'Аспект: Огонь'),
        (ROOT / 'assets/portraits/aspect_forest.png',     'Аспект: Лес'),
        (ROOT / 'assets/portraits/aspect_heaven.png',     'Аспект: Небеса'),
    ]
    chars = [(ROOT / 'assets/sprites/player.png', 'Игрок')]
    for p in sorted((ROOT / 'assets/sprites/enemies').glob('*.png')):
        if p.stem == 'manekin':
            continue
        chars.append((p, label_for_enemy(p.stem)))

    max_w, max_h = 0, 0
    for path, _ in chars:
        im = Image.open(path)
        max_w = max(max_w, im.width)
        max_h = max(max_h, im.height)

    SPRITE_PAD = 18
    LABEL_H = 32
    C_CELL_W = max(max_w + SPRITE_PAD * 2, 175)
    C_CELL_H = max_h + SPRITE_PAD + LABEL_H + 6
    C_GAP = 14

    W = 1280
    cols = 6
    rows = math.ceil(len(chars) / cols)

    P_CELL_W = 180
    P_CELL_H = 240
    P_GAP = 24

    header_h = 152
    portrait_block_h = 34 + P_CELL_H + 12
    section_gap = 36
    chars_block_h = 34 + rows * C_CELL_H + (rows - 1) * C_GAP
    H = header_h + portrait_block_h + section_gap + chars_block_h + BOTTOM_PAD

    img = gradient_bg((W, H))
    draw = ImageDraw.Draw(img, 'RGBA')

    y = header(draw, W, 30, 'Персонажи и портреты')

    y = section_label(draw, 'ПОРТРЕТЫ', W, y - 4)
    portraits_total_w = len(portraits) * P_CELL_W + (len(portraits) - 1) * P_GAP
    px_start = (W - portraits_total_w) // 2
    for i, (path, lbl) in enumerate(portraits):
        x = px_start + i * (P_CELL_W + P_GAP)
        draw_realsize_cell(img, x, y, P_CELL_W, P_CELL_H, path, lbl,
                           sprite_max_w=P_CELL_W - 20,
                           sprite_max_h=P_CELL_H - 36 - 12,
                           sprite_pad_top=10, label_h=36, font_size=17)
    y += P_CELL_H + section_gap

    y = section_label(draw, 'ИГРОК · ВРАГИ', W, y)
    for i, (path, lbl) in enumerate(chars):
        row = i // cols
        col = i % cols
        in_this_row = min(cols, len(chars) - row * cols)
        rw = in_this_row * C_CELL_W + (in_this_row - 1) * C_GAP
        rx = (W - rw) // 2
        x = rx + col * (C_CELL_W + C_GAP)
        cy = y + row * (C_CELL_H + C_GAP)
        draw_realsize_cell(img, x, cy, C_CELL_W, C_CELL_H, path, lbl,
                           sprite_max_w=max_w, sprite_max_h=max_h,
                           sprite_pad_top=SPRITE_PAD, label_h=LABEL_H, font_size=15)

    out = OUT / '01_characters.png'
    img.save(out, 'PNG')
    print(f'wrote {out.relative_to(ROOT)}  ({W}x{H})')


# ============================================================
# SHEET 2 — Skill icons
# ============================================================
def sheet_skill_icons():
    icons = sorted((ROOT / 'assets/icons/skills').glob('*.png'))
    cols = 6
    rows = math.ceil(len(icons) / cols)
    CELL_W, CELL_H = 185, 140
    GAP = 14
    LABEL_H = 32

    W = cols * CELL_W + (cols - 1) * GAP + 80
    header_h = 142
    grid_h = rows * CELL_H + (rows - 1) * GAP
    H = header_h + grid_h + BOTTOM_PAD

    img = gradient_bg((W, H))
    draw = ImageDraw.Draw(img, 'RGBA')
    header(draw, W, 24, f'Иконки умений · {len(icons)} спрайта')

    grid_x = (W - (cols * CELL_W + (cols - 1) * GAP)) // 2
    grid_y = header_h
    for i, path in enumerate(icons):
        row = i // cols
        col = i % cols
        x = grid_x + col * (CELL_W + GAP)
        y = grid_y + row * (CELL_H + GAP)
        ru_name = RU.get(f'{path.stem}_name', path.stem.replace('_', ' ').title())
        draw_realsize_cell(img, x, y, CELL_W, CELL_H, path, ru_name,
                           sprite_max_w=CELL_W - 20,
                           sprite_max_h=CELL_H - LABEL_H - 16,
                           sprite_pad_top=12, label_h=LABEL_H, font_size=14)

    out = OUT / '02_skill_icons.png'
    img.save(out, 'PNG')
    print(f'wrote {out.relative_to(ROOT)}  ({W}x{H})')


# ============================================================
# SHEET 3 — Tiles, objects, atlases
# ============================================================
def sheet_tiles():
    hex_tiles = sorted((ROOT / 'assets/tiles').glob('tile_*.png'))
    grass = ROOT / 'scenes/dev/godmode_atlas.png'

    hex_label_map = {
        'tile_heaven_1': 'Небо 1',
        'tile_heaven_2': 'Небо 2',
        'tile_heaven_3': 'Небо 3',
        'tile_lava_1':   'Лава 1',
        'tile_lava_2':   'Лава 2',
    }
    hex_tiles_with_labels = [(grass, 'Трава')] + [
        (p, hex_label_map.get(p.stem, p.stem)) for p in hex_tiles
    ]

    objects = [
        (ROOT / 'assets/tiles/tree.png',           'Дерево'),
        (ROOT / 'assets/tiles/column.png',         'Колонна'),
        (ROOT / 'assets/tiles/ball.png',           'Мяч'),
        (ROOT / 'assets/tiles/object_computer.png','Компьютер'),
        (ROOT / 'assets/tiles/object_cooler.png',  'Кулер'),
        (ROOT / 'assets/tiles/object_heal.png',    'Лечение'),
        (ROOT / 'assets/tiles/object_lava.png',    'Лава'),
        (ROOT / 'assets/tiles/object_on_chair.png','На стуле'),
        (ROOT / 'assets/tiles/object_raf.png',     'Раф'),
    ]
    max_ow, max_oh = 0, 0
    for path, _ in objects:
        im = Image.open(path)
        max_ow = max(max_ow, im.width)
        max_oh = max(max_oh, im.height)

    atlas_path = ROOT / 'scenes/arena/tilesets/hex_atlas.png'
    atlas_img = Image.open(atlas_path).convert('RGBA')

    W = 1280
    header_h = 142

    atlas_target_w = W - 100
    atlas_scale = atlas_target_w / atlas_img.width
    atlas_h = int(atlas_img.height * atlas_scale)
    banner_label_h = 34
    banner_block_h = banner_label_h + atlas_h + 12
    banner_caption_h = 26
    section_gap = 38

    HT_CELL_W = 200
    HT_CELL_H = 80 + 18 + 32 + 4
    HT_GAP = 16
    ht_cols = min(6, len(hex_tiles_with_labels))
    ht_rows = math.ceil(len(hex_tiles_with_labels) / ht_cols)
    hex_label_h = 34
    hex_grid_h = ht_rows * HT_CELL_H + (ht_rows - 1) * HT_GAP
    hex_block_h = hex_label_h + hex_grid_h + 8

    OB_PAD = 18
    OB_LABEL_H = 32
    OB_CELL_W = max(max_ow + OB_PAD * 2, 165)
    OB_CELL_H = max_oh + OB_PAD + OB_LABEL_H + 4
    OB_GAP = 14
    ob_cols = 5
    ob_rows = math.ceil(len(objects) / ob_cols)
    ob_label_h = 34
    ob_grid_h = ob_rows * OB_CELL_H + (ob_rows - 1) * OB_GAP
    ob_block_h = ob_label_h + ob_grid_h + 8

    H = (header_h
         + banner_block_h + banner_caption_h + section_gap
         + hex_block_h + section_gap
         + ob_block_h
         + BOTTOM_PAD)

    img = gradient_bg((W, H))
    draw = ImageDraw.Draw(img, 'RGBA')
    y = header(draw, W, 24, 'Тайлы, объекты и атласы')

    y = section_label(draw, 'HEX ATLAS — scenes/arena/tilesets/hex_atlas.png', W, y - 4)
    atlas_scaled = atlas_img.resize(
        (int(atlas_img.width * atlas_scale), atlas_h),
        Image.LANCZOS if atlas_scale < 1 else Image.NEAREST
    )
    ax = (W - atlas_scaled.width) // 2
    draw.rounded_rectangle((ax - 4, y - 4, ax + atlas_scaled.width + 4, y + atlas_h + 4),
                           radius=4, outline=ACCENT_DIM, width=1)
    img.paste(atlas_scaled, (ax, y), atlas_scaled)
    y += atlas_h + 8
    y = caption_line(draw,
                     '8 вариантов 128×80, склеенных в одну полосу:  2× лес · 3× небо · 2× лава · 1× офис',
                     W, y)
    y += section_gap - 8

    y = section_label(draw, 'ВАРИАНТЫ ГЕКСОВ', W, y)
    for i, (path, lbl) in enumerate(hex_tiles_with_labels):
        row = i // ht_cols
        col = i % ht_cols
        in_this_row = min(ht_cols, len(hex_tiles_with_labels) - row * ht_cols)
        rw = in_this_row * HT_CELL_W + (in_this_row - 1) * HT_GAP
        rx = (W - rw) // 2
        x = rx + col * (HT_CELL_W + HT_GAP)
        cy = y + row * (HT_CELL_H + HT_GAP)
        draw_realsize_cell(img, x, cy, HT_CELL_W, HT_CELL_H, path, lbl,
                           sprite_max_w=128, sprite_max_h=80,
                           sprite_pad_top=18, label_h=32, font_size=15)
    y += hex_grid_h + section_gap

    y = section_label(draw, 'ОБЪЕКТЫ НА ТАЙЛАХ', W, y)
    for i, (path, lbl) in enumerate(objects):
        row = i // ob_cols
        col = i % ob_cols
        in_this_row = min(ob_cols, len(objects) - row * ob_cols)
        rw = in_this_row * OB_CELL_W + (in_this_row - 1) * OB_GAP
        rx = (W - rw) // 2
        x = rx + col * (OB_CELL_W + OB_GAP)
        cy = y + row * (OB_CELL_H + OB_GAP)
        draw_realsize_cell(img, x, cy, OB_CELL_W, OB_CELL_H, path, lbl,
                           sprite_max_w=max_ow, sprite_max_h=max_oh,
                           sprite_pad_top=OB_PAD, label_h=OB_LABEL_H, font_size=15)

    out = OUT / '03_tiles_atlases.png'
    img.save(out, 'PNG')
    print(f'wrote {out.relative_to(ROOT)}  ({W}x{H})')


# ============================================================
# SHEET 4 — Skills with descriptions
# ============================================================
def sheet_skills_with_desc():
    icons = sorted((ROOT / 'assets/icons/skills').glob('*.png'))
    entries = []
    for p in icons:
        sid = p.stem
        name = RU.get(f'{sid}_name', sid)
        desc = RU.get(f'{sid}_desc', '')
        tip  = RU.get(f'{sid}_tooltip', '')
        entries.append((p, name, desc, tip))

    W = 1280
    cols = 2
    rows = math.ceil(len(entries) / cols)

    ROW_H = 128
    COL_W = (W - 80) // cols
    COL_GAP = 24
    ICON_SIZE = 64
    ICON_PAD = 16
    TEXT_PAD = 16

    header_h = 142
    grid_h = rows * ROW_H + (rows - 1) * 8
    H = header_h + 34 + grid_h + BOTTOM_PAD

    img = gradient_bg((W, H))
    draw = ImageDraw.Draw(img, 'RGBA')
    y = header(draw, W, 24, f'Каталог умений · {len(entries)} штуки')
    y = section_label(draw, 'СКИЛЛЫ И ОПИСАНИЯ', W, y - 4)

    name_fnt = font(17, bold=True)
    desc_fnt = font(15, bold=False)
    tip_fnt  = font(13, bold=False, italic=True)

    grid_w = cols * COL_W + (cols - 1) * COL_GAP
    grid_x = (W - grid_w) // 2

    for i, (path, name, desc, tip) in enumerate(entries):
        row = i // cols
        col = i % cols
        x = grid_x + col * (COL_W + COL_GAP)
        cy = y + row * (ROW_H + 8)

        card = Image.new('RGBA', (COL_W, ROW_H), (0, 0, 0, 0))
        cdraw = ImageDraw.Draw(card)
        cdraw.rounded_rectangle((0, 0, COL_W - 1, ROW_H - 1), radius=8,
                                fill=CELL_BG + (200,),
                                outline=CELL_EDGE + (255,), width=1)

        try:
            ic = Image.open(path).convert('RGBA')
            ix = ICON_PAD
            iy = (ROW_H - ic.height) // 2
            card.paste(ic, (ix, iy), ic)
        except Exception:
            pass

        tx = ICON_PAD + ICON_SIZE + TEXT_PAD
        text_max_w = COL_W - tx - ICON_PAD

        ty = 14
        cdraw.text((tx, ty), name, fill=ACCENT, font=name_fnt)
        ty += text_h(cdraw, name, name_fnt) + 8

        desc_lines = wrap_text(cdraw, desc, desc_fnt, text_max_w)[:2]
        for line in desc_lines:
            cdraw.text((tx, ty), line, fill=LABEL, font=desc_fnt)
            ty += text_h(cdraw, line, desc_fnt) + 3

        if tip:
            t = tip
            while text_w(cdraw, t, tip_fnt) > text_max_w and len(t) > 4:
                t = t[:-1]
            if t != tip:
                t = t.rstrip() + '…'
            cdraw.text((tx, ROW_H - 26), t, fill=LABEL_VDIM, font=tip_fnt)

        img.paste(card, (x, cy), card)

    out = OUT / '04_skills.png'
    img.save(out, 'PNG')
    print(f'wrote {out.relative_to(ROOT)}  ({W}x{H})')


# ============================================================
# SHEET 5 — Game functionality overview
# ============================================================
def sheet_features():
    sections = [
        ('ДИЗАЙН-СТОЛПЫ', [
            'Полная видимость информации — игрок видит всё перед каждым решением',
            'Симметрия игрока и монстра — общие контракты Actor / Ability',
            'Без скрытого RNG, без внезапного урона, всё телеграфируется',
        ]),
        ('РЕЖИМЫ И РЕДАКТОРЫ', [
            'Сюжетная кампания (story_campaign.game.json)',
            'Песочница Godmode — спавн манекенов, фри-каст',
            'Загрузка кастомного уровня (.json) или кампании (.game.json)',
            'Редактор карт — террейн, объекты, волны, диалоги, скилл-офферы',
            'Редактор кампаний — сшивка карт + интро-катсцены',
        ]),
        ('БОЕВАЯ СИСТЕМА', [
            'Пошаговая боёвка на гекс-арене, мир тикает по ходу игрока',
            'Спелл-крафт через модификаторы: Target × Effect × Modifier',
            'Стэкуемые статус-эффекты с иммунитетами и dispel-логикой',
            'AI-планировщик с поведенческими сценариями (data/ai_behaviors/)',
            'Точные телеграфы атак с числами урона',
        ]),
        ('ROGUELIKE-ПЕТЛЯ', [
            'Волны врагов с таймлайном и пулом противников',
            'Выбор скилла между волнами (skill offer pools)',
            'Mood-counter — настроение героини меняет её портрет',
            'Поглощение трупов — биом-тинт и финальный шейк камеры',
            'Система очков забега (RunScore)',
        ]),
        ('НАРРАТИВ И ПРЕЗЕНТАЦИЯ', [
            'Диалоговая система с триггерами, привязанными к уровню',
            'Интро-катсцена с CutscenePlayer + IntroDirector',
            'Шейдерные переходы между уровнями (wobble / chroma / fade)',
            'Генератор процедурной музыки (Conductor / Harmony / StateMixer)',
            'CRT post-FX для ретро-вайба',
            'Floating numbers, hit-flash, camera shake',
        ]),
        ('ТЕХНИЧЕСКИЙ СТЕК', [
            'Godot 4.6.2 stable + GDScript',
            '220 файлов · 18 687 строк кода (без комментариев)',
            '10 шейдеров · 251 строка',
            '41 спека + 11 фиксов в specs/',
            'JSON-контент в data/',
            'EventBus для cross-module связи, GameSpeed для всех таймингов',
        ]),
    ]

    W = 1280
    cols = 3
    rows = math.ceil(len(sections) / cols)

    CARD_GAP = 20
    CARD_W = (W - 80 - (cols - 1) * CARD_GAP) // cols
    CARD_PAD_X = 22
    CARD_PAD_Y = 20
    HEAD_FNT = font(19, bold=True)
    BULLET_FNT = font(15, bold=False)
    BULLET_GAP = 8
    HEAD_BOTTOM = 16
    BULLET_INDENT = 16

    header_h = 142

    tmp_img = Image.new('RGB', (10, 10))
    tmp_draw = ImageDraw.Draw(tmp_img)
    card_heights = []
    for title, bullets in sections:
        h = CARD_PAD_Y + text_h(tmp_draw, title, HEAD_FNT) + HEAD_BOTTOM
        bullet_max_w = CARD_W - CARD_PAD_X * 2 - BULLET_INDENT
        for b in bullets:
            lines = wrap_text(tmp_draw, b, BULLET_FNT, bullet_max_w)
            line_h = text_h(tmp_draw, 'Aj', BULLET_FNT)
            h += len(lines) * (line_h + 4) + BULLET_GAP
        h += CARD_PAD_Y - BULLET_GAP
        card_heights.append(h)

    row_heights = []
    for r in range(rows):
        row_cards = card_heights[r * cols:(r + 1) * cols]
        row_heights.append(max(row_cards))

    grid_h = sum(row_heights) + (rows - 1) * CARD_GAP
    H = header_h + 34 + grid_h + BOTTOM_PAD

    img = gradient_bg((W, H))
    draw = ImageDraw.Draw(img, 'RGBA')
    y = header(draw, W, 24, 'Основной функционал игры')
    total_bullets = sum(len(s[1]) for s in sections)
    y = section_label(draw, f'ОБЗОР · {total_bullets} пунктов', W, y - 4)

    grid_total_w = cols * CARD_W + (cols - 1) * CARD_GAP
    grid_x = (W - grid_total_w) // 2

    cy = y
    for r in range(rows):
        row_h = row_heights[r]
        for c in range(cols):
            idx = r * cols + c
            if idx >= len(sections):
                continue
            title, bullets = sections[idx]
            cx = grid_x + c * (CARD_W + CARD_GAP)

            card = Image.new('RGBA', (CARD_W, row_h), (0, 0, 0, 0))
            cdraw = ImageDraw.Draw(card)
            cdraw.rounded_rectangle((0, 0, CARD_W - 1, row_h - 1), radius=10,
                                    fill=CELL_BG + (210,),
                                    outline=CELL_EDGE + (255,), width=1)
            cdraw.rounded_rectangle((0, 0, CARD_W - 1, 4), radius=2, fill=ACCENT_DIM)

            ty = CARD_PAD_Y
            cdraw.text((CARD_PAD_X, ty), title, fill=ACCENT, font=HEAD_FNT)
            ty += text_h(cdraw, title, HEAD_FNT) + HEAD_BOTTOM

            bullet_max_w = CARD_W - CARD_PAD_X * 2 - BULLET_INDENT
            for b in bullets:
                cdraw.text((CARD_PAD_X, ty - 1), '•', fill=ACCENT_DIM, font=BULLET_FNT)
                lines = wrap_text(cdraw, b, BULLET_FNT, bullet_max_w)
                line_h = text_h(cdraw, 'Aj', BULLET_FNT)
                for line in lines:
                    cdraw.text((CARD_PAD_X + BULLET_INDENT, ty), line,
                               fill=LABEL, font=BULLET_FNT)
                    ty += line_h + 4
                ty += BULLET_GAP

            img.paste(card, (cx, cy), card)
        cy += row_h + CARD_GAP

    out = OUT / '05_features.png'
    img.save(out, 'PNG')
    print(f'wrote {out.relative_to(ROOT)}  ({W}x{H})')


def main():
    sheet_characters()
    sheet_skill_icons()
    sheet_tiles()
    sheet_skills_with_desc()
    sheet_features()
    print('\ndone.')


if __name__ == '__main__':
    main()
