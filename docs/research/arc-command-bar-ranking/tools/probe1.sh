#!/bin/zsh
# probe1.sh <name> <query>: open Arc's command bar with Cmd+T, type the query, wait, capture Arc's window and its AX texts, close with Esc.
set -e
name=$1; q=$2; out=/tmp/cbr/live
osascript -e 'tell application "System Events" to tell process "Arc" to set frontmost to true'; sleep 0.6
tw=$(/tmp/cbr/bin/topwin 960 300)
echo "topwin $tw"
case "$tw" in Arc*) ;; *) echo "not Arc on top, stop"; exit 3;; esac
osascript -e 'tell application "System Events" to keystroke "t" using command down'; sleep 1.2
/Users/administrator/.t3/projects/brk/scripts/station/typeslow.sh "$q"
sleep 2.5
wid=$(/tmp/cbr/bin/wins Arc | awk -F'|' '$3 ~ /1280x776/ && $5=="onscreen 1" {print $1; exit}')
screencapture -x -o -l "$wid" "$out/$name.png"
osascript /tmp/cbr/tools/axrows.applescript > "$out/$name.ax.txt" 2>&1 || true
osascript -e 'tell application "System Events" to key code 53'; sleep 0.4
osascript -e 'tell application "System Events" to key code 53'; sleep 0.4
echo "done $name $(wc -l < $out/$name.ax.txt) ax lines"
