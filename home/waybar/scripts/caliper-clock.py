#!/usr/bin/env python3
import datetime
import json

AM_OBJECTS = {
    0:  "A speck",
    1:  "A mite",
    2:  "A poppy",
    3:  "A sesame",
    4:  "A lentil",
    5:  "A kernel",
    6:  "A corn pop",
    7:  "A blueberry",
    8:  "A chestnut",
    9:  "A sugar cube",
    10: "A small cork",
    11: "A Matchbox car",
    12: "A film canister",
}

PM_OBJECTS = {
    12: "A harmonica",
    11: "A lighter",
    10: "A pocket watch",
    9:  "A thimble",
    8:  "A die",
    7:  "A pill",
    6:  "A BB",
    5:  "A bead",
    4:  "A fleck",
    3:  "A grain",
    2:  "A spore",
    1:  "A mote",
    0:  "A ghost",
}

MAX_ARMS = 10

def arm(level):
    length = round(level * MAX_ARMS / 12)
    return "━" * length

def format_time(now):
    hour_24 = now.hour
    is_pm = hour_24 >= 12
    distance_from_noon = abs(hour_24 - 12)
    level = 12 - distance_from_noon
    objects = PM_OBJECTS if is_pm else AM_OBJECTS
    obj = objects[level]
    a = arm(level)
    time_str = now.strftime("%-I:%M %p")
    jaw = f"{a}┤ {obj} ├{a}" if a else f"┤{obj}├"
    return jaw, time_str

if __name__ == "__main__":
    now = datetime.datetime.now()
    jaw, time_str = format_time(now)
    text = f"{jaw}  {time_str}"
    weekday  = now.strftime("%A")
    date_str = now.strftime("%-d %B %Y")
    tooltip = f"<span foreground='#908caa'>{weekday}</span>, <span foreground='#e0def4'>{date_str}</span>"
    print(json.dumps({"text": text, "tooltip": tooltip}))
