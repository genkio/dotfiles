#!/bin/sh

# Month before day, matching what this machine's en_JP locale resolves `%x` to.
# The demo config this started from was day-first, which is neither the locale
# nor the standard.
#
# LC_TIME only reaches `%a`, everything else in the format is digits. The
# Japanese abbreviated weekday is the single kanji 月..日, which is the point:
# one glyph, no ambiguity with the month number next to it.

sketchybar --set "$NAME" label="$(LC_TIME=ja_JP.UTF-8 date '+%m/%d %H:%M %a')"
