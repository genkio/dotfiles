#!/bin/sh

sketchybar --set "$NAME" label="$(LC_TIME=ja_JP.UTF-8 date '+%m/%d %H:%M %a')"
