#!/bin/bash
# Compiles the small Swift helpers used by the capture scripts into tools/bin (once; rebuilt when a source is newer).
#   mouse   click|rightclick|dblclick|move x y | drag x1 y1 x2 y2 [hold]     real mouse events (screen points)
#   key     down|up|tap <name> [mods]                                          real key events
#   wins    <OwnerName>                                                       window list: id|title|x,y wxh|layer|onscreen|pid
#   scan    <png> row|col <n> [lo hi]                                          colour transitions along a line (pixels)
#   pair    <left> <right> <out>                                               side-by-side at half scale
#   compose <base> <out> <overlay> <dx> <dy> ...                               paste menu windows onto a window capture
#   sheet   <out> <label> <arc> <brk> ...                                      Arc | Brk | diff rows with diff share
#   dragback <x1> <y1> <x2> <y2> <hold> <signal> [<release>]                             drag, hold for a capture, return without dropping
#   scroll  <lines>                                                            scroll wheel at the pointer
#   moddrag <x1> <y1> <x2> <y2> <hold>                                           drag with shift+cmd held on every event
#   regions <arc> <brk> [--out f] [--crop x y w h]                               the differing blocks, biggest first, each with the shift of the Brk image that would fix it
#   bands   <arc> <brk> x y w h                                                  the rows of ink in a rectangle of each image, side by side
#   pathdrag <pause> x0 y0 x1 y1 [...] [--signal f --release f] [--back]         a drag through several points; held for a capture; back to the start without dropping
#   press   <x> <y> <hold> <signal>                                              mouse down without moving, held for a capture
#   dropzone <png>...                                                            which drop preview a 1280 x 776 pt window capture shows (Q17)
#   gest    <x> <y> <ms> [--may] [--began dx,dy] <steps> [--wait s] [--shot png winid] ... [--end]  a two-finger gesture on the real path; real Arc takes it when the first event has sideways travel (Q19)
# compile next to this script whatever folder the caller is in (the station runs it from a station worktree)
cd "$(dirname "$0")"
mkdir -p bin
for src in mouse key wins-any scan pair compose sheet dragback scroll moddrag regions bands pathdrag press cut topwin dropzone gest; do
  out="bin/${src%-any}"
  # rebuild only when the source content changed (git checkouts touch mtimes without changing anything)
  sum="$(shasum -a 256 "$src.swift" | cut -c1-16)"
  if [ ! -x "$out" ] || [ "$(cat "$out.sha" 2>/dev/null)" != "$sum" ]; then
    # compile to a private name and move it into place, so a concurrent caller never runs a half-written binary
    tmp="$out.$$.tmp"
    if swiftc -O -o "$tmp" "$src.swift" 2>&1 | grep -v "warning:"; then :; fi
    [ -x "$tmp" ] && mv -f "$tmp" "$out" && echo "$sum" > "$out.sha" && echo "[helpers] built $out"
  fi
done
