#!/bin/bash
# Try semantic cutoffs live (not saved: a Quickshell reload restores the defaults in Launcher.qml).
# usage: sweep.sh "min min1 win adj" ...
for cfg in "$@"; do
  qs ipc call launcher tune $cfg; sleep 0.5
  for i in $(seq 120); do [ "$(qs ipc call launcher indexing)" = false ] && break; sleep 1; done
  python3 -I evaluate.py --no-lexical-baseline --out /dev/null 2>&1 | awk -v c="$cfg" '
    /^  (ALL|none-web|near-miss|act-intent|app-intent|key-intent|day|act-short|app-generic) / {r[$1]=$3}
    END {printf "%-22s ALL %s | none %s near %s | act-int %s app-int %s key-int %s | day %s act-short %s app-gen %s\n", c, r["ALL"], r["none-web"], r["near-miss"], r["act-intent"], r["app-intent"], r["key-intent"], r["day"], r["act-short"], r["app-generic"]}'
done
