#!/usr/bin/env python3
# eggclock.py — egg timer for Waybar with hatch logic, rare golden egg, and no back-to-back repeats

import json
import os
import random
import sys
from datetime import datetime
from pathlib import Path

EGG_ANIMALS = [
    "🐣", "🐥", "🐤", "🐔", "🐓", "🐦", "🐧", "🐸", "🐢", "🦎", "🐊", "🐍",
    "🦆", "🦅", "🦉", "🐠", "🐟", "🐡", "🦐", "🦑", "🪺", "🐛", "🦋", "🐜",
    "🪲", "🐝", "🦖", "🦄",
]

LORE = {
    "🐣": "Baby chicks hatch from their moms. -Clementine",
    "🐥": "Baby Chick is confused. -Clementine",
    "🐤": "Baby Chick is turning around, not caring. - Clementine",
    "🐔": "Chickens are 'Henry's.",
    "🐓": "Rises early. Crow optional.",
    "🐦": "Spies on you from trees.",
    "🐧": "AHHHH SO COLD SO COLD--it's freezing.",
    "🐸": "Hop. Hop. Hop Hop Hop; Ne. Ver. Stop.",
    "🐢": "What the heck...?",
    "🦎": "Lizards are slimy and nice.",
    "🐊": "See you later, Crocodile.",
    "🐍": "Snakes look a their own butts.",
    "🦆": "Mallard.",
    "🦅": "President Razor Pigeon.",
    "🦉": "Knows something you don't.",
    "🐠": "Just keep...something...",
    "🐟": "Just a fish. Or is it?",
    "🐡": "Fugu? More like 'FU, GUY!'.",
    "🦐": "Gimme summa dem scrampies.",
    "🦑": "Ink-based defense mechanism. Respect.",
    "🪺": "Home is wherever it lands.",
    "🐛": "Ambiguous intentions.",
    "🦋": "Proof that change is real.",
    "🐜": "Collectivist. Ruthless. Inspiring.",
    "🪲": "Slow and something.",
    "🐝": "Make that honey.",
    "🦖": "Rawr, and all that...",
    "🦄": "Boo! I see you!",
}

TOTAL_ANIMALS = len(EGG_ANIMALS)

state_dir = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "eggclock"
state_dir.mkdir(parents=True, exist_ok=True)
last_hatch_file = state_dir / "last_hatch"
seen_file = state_dir / "seen_animals.json"
golden_count_file = state_dir / "golden_egg_count"


def load_seen() -> set:
    try:
        return set(json.loads(seen_file.read_text()))
    except (FileNotFoundError, json.JSONDecodeError, ValueError):
        return set()


def save_seen(seen: set) -> None:
    seen_file.write_text(json.dumps(sorted(seen)))


def load_golden_count() -> int:
    try:
        return int(golden_count_file.read_text().strip())
    except (FileNotFoundError, ValueError):
        return 0


def save_golden_count(n: int) -> None:
    golden_count_file.write_text(str(n))


def animal_tooltip(lore: str, seen: set, golden_count: int) -> str:
    return f"{lore}\n\nYou've found {len(seen)}/{TOTAL_ANIMALS} animals!\nGolden eggs found: {golden_count}"


def golden_tooltip(golden_count: int, animal_count: int) -> str:
    return f"I WANT IT NOOOOOOOOOWWWWW!!!!!\n\nGolden eggs found: {golden_count}\nAnimals found: {animal_count}/{TOTAL_ANIMALS}"


def output(text: str, tooltip: str) -> None:
    print(json.dumps({"text": text, "tooltip": tooltip}))


now = datetime.now()
current_min = now.minute
remaining_min = 60 - current_min

if current_min == 0:
    if last_hatch_file.exists():
        hatched = last_hatch_file.read_text().strip()
        if hatched == "🥚✨":
            gold = load_golden_count()
            seen = load_seen()
            output("🥚✨ Golden Egg!", golden_tooltip(gold, len(seen)))
            sys.exit(0)
        elif hatched in LORE:
            seen = load_seen()
            seen.add(hatched)
            save_seen(seen)
            gold = load_golden_count()
            output(hatched, animal_tooltip(LORE[hatched], seen, gold))
            sys.exit(0)

    # 1% chance of golden egg
    if random.randint(0, 99) == 0:
        gold = load_golden_count() + 1
        save_golden_count(gold)
        last_hatch_file.write_text("🥚✨")
        seen = load_seen()
        output("🥚✨ Golden Egg!", golden_tooltip(gold, len(seen)))
        sys.exit(0)

    # Weighted pool (🦄 has 5x weight)
    weighted = []
    for egg in EGG_ANIMALS:
        weighted.extend([egg] * (5 if egg == "🦄" else 1))

    last_hatch = last_hatch_file.read_text().strip() if last_hatch_file.exists() else ""
    candidates = [e for e in weighted if e != last_hatch]
    hatched = random.choice(candidates)
    last_hatch_file.write_text(hatched)

    seen = load_seen()
    seen.add(hatched)
    save_seen(seen)
    gold = load_golden_count()
    output(hatched, animal_tooltip(LORE[hatched], seen, gold))
    sys.exit(0)

# Waiting messages
if remaining_min >= 51:
    msg = "Long way to go..."
elif remaining_min >= 41:
    msg = "Count to triangle..."
elif remaining_min >= 31:
    msg = "Almost Halfway..."
elif remaining_min >= 21:
    msg = "Medium Roast..."
elif remaining_min >= 11:
    msg = "It's bubbling..."
elif remaining_min >= 1:
    msg = "The egg is bright and clean..."
else:
    msg = "Any second now…"

output(f"🥚 {remaining_min} min to hatch", msg)
