#!/usr/bin/env bash
# Car Surface FX in-game QA: forces each effect with carSurfaceFx.debug(), reads carSurfaceFx.status() / screenInfo() back as the check, and takes a named screenshot of each.
# The game must be up with a car on any level (the same arrangement as qa_game/run.sh --no-launch); this script launches and kills nothing.
#
#   bash tools/qa/csfx_qa.sh [--only a,b,c]       sections: overlay glass paint dirt wipers frost snow bugs spray scrape
#   QA_SHOT_DIR=<dir>  where the screenshots go (default: the wc\morning folder), named surfacefx_<check>.jpg
#   QA_CONTROL=<dir>   the control repo whose tools/qa_game/lib.sh (R, SHOT, rec) is used (read only), default /c/Dev/SLRR BeamNG Graph
# Wired into the control suite as:  csfx) bash "/c/Dev/BeamNG Car Surface FX/tools/qa/csfx_qa.sh" ;;
# Results: PASS/FAIL/INFO rows, and tools/qa/last_report.md (not committed). A FAIL row quotes the status line that failed.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL="${QA_CONTROL:-/c/Dev/SLRR BeamNG Graph}"
source "$CONTROL/tools/qa_game/lib.sh" || { echo "no lib.sh in $CONTROL/tools/qa_game"; exit 2; }
OUT="${QA_SHOT_DIR:-/c/Users/Connor/AppData/Local/Temp/wc/morning}"
mkdir -p "$OUT"

ONLY=""
while [ $# -gt 0 ]; do case "$1" in --only) ONLY=",$2,"; shift ;; *) echo "unknown option $1"; exit 2 ;; esac; shift; done
want() { [ -z "$ONLY" ] || case "$ONLY" in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

status() { R "return carSurfaceFx.status()" | tr -d '\r'; }
info()   { R "return carSurfaceFx.screenInfo()" | tr -d '\r'; }
dbg()    { R "return carSurfaceFx.debug($1)" > /dev/null; }
cam()    { R "core_camera.setByName(0, '$1') return 1" > /dev/null; }
shot()   { local f; f="$(SHOT "$1")"; cp -f "$f" "$OUT/surfacefx_$1.jpg" 2>/dev/null; }
# expect <name> <extended regex> <text> : PASS when the regex matches the text
expect() { if printf '%s' "$3" | grep -Eq "$2"; then rec "$1" PASS "$3"; else rec "$1" FAIL "wanted /$2/: $3"; fi; }

# the mod is loaded and the game has a player car
R0="$(R "return type(carSurfaceFx) == 'table' and carSurfaceFx.apiVersion or 'missing'")"
expect "mod loaded" '^2' "$R0"
[ "$(printf '%s' "$R0" | head -c 1)" = "2" ] || { echo "Car Surface FX is not loaded in the running game"; exit 1; }
dbg ""
nap 2

if want overlay; then
  dbg "'rain', 1"; cam driver; nap 25
  expect "cockpit overlay on (hull, driver cam, wet)" 'want=true hull=[0-9]+ on=true' "$(info)"
  shot cockpit_rain
fi

if want glass; then
  dbg "'rain', 1"; cam external; nap 8
  expect "window canvases bound" 'vivace_glass=r1|glass[A-Za-z_]*=r1' "$(status)"
  shot glass_outside
fi

if want paint; then
  dbg "'rain', 1"; cam external; nap 30
  expect "wet paint rung" 'rung [1-5]' "$(status)"
  shot paint_beads
fi

if want dirt; then
  dbg "'mud', 0.9"; dbg "'rain', 0"; cam external; nap 4
  expect "mud forced" 'forced true' "$(status)"
  shot mud
  dbg "'dust', 0.9"; nap 3; shot dust
  dbg ""
fi

if want wipers; then
  dbg "'rain', 1"; dbg "'wiper', 1"; cam driver; nap 20
  for i in 1 2 3 4; do shot "wiper_$i"; nap 0.3; done
  expect "wipers forced reach the overlay" 'wiper=1' "$(status)"
  dbg "'wiper', 0"; nap 5; shot wiper_after
  dbg ""
fi

if want frost; then
  dbg "'rain', 0"; dbg "'frost', 1"; cam external; nap 6
  expect "frost forced" 'frost 1\.00' "$(status)"
  shot frost_out
  cam driver; nap 3; shot frost_cockpit
  dbg "'wiper', 1"; nap 6; shot wiper_frost
  dbg "'frost', 0.4"; nap 3; shot frost_light
  dbg ""
  # real build and clear: a cold night, a cold engine (then a warm one)
  dbg "'air', -6"; nap 60
  rec "frost builds in the cold (60 s)" INFO "$(status)"
  dbg ""
fi

if want snow; then
  dbg "'snow', 0.9"; cam external; nap 5
  expect "snow forced" 'snow 0\.9' "$(status)"
  shot snow
  dbg ""
  dbg "'air', -3"; dbg "'snowing', 1"; nap 60
  expect "a standing car takes snow" 'snow 0\.[3-9]|snow 1' "$(status)"
  shot snowfall
  dbg ""
fi

if want bugs; then
  dbg "'bugs', 1"; cam external; nap 5
  expect "bugs forced" 'bugs 1\.00' "$(status)"
  shot bugs
  dbg ""
fi

if want spray; then
  dbg "'rain', 1"; dbg "'spray', 0.8"; cam driver; nap 8
  expect "spray forced" 'spray 0\.[5-9]' "$(status)"
  shot spray_cockpit
  dbg ""
fi

if want scrape; then
  # the car looks for the nearest wall, is put 20 m back from it at about 12 degrees toward it and driven into it; the scratch count must go up
  dbg ""
  N0="$(R "return carSurfaceFx_scratch and carSurfaceFx_scratch.count(be:getPlayerVehicleID(0)) or -1" | tr -d '\r')"
  R "local v=be:getPlayerVehicle(0) local p=v:getPosition() local bd,ba=99,0
for a=0,355,5 do local r=math.rad(a) local h=castRayStatic(p+vec3(0,0,0.5),vec3(math.cos(r),math.sin(r),0),60) if h<bd then bd=h ba=a end end
local r=math.rad(ba) local n=vec3(math.cos(r),math.sin(r),0) local t=vec3(-n.y,n.x,0)
local c,s=math.cos(math.rad(12)),math.sin(math.rad(12))
spawn.safeTeleport(v, p+n*bd-n*20+vec3(0,0,0.4), quatFromDir(t*c+n*s, vec3(0,0,1)), true, nil, nil, nil, false)
v:queueLuaCommand('input.event(\"throttle\",1)') return bd" > /dev/null
  nap 7
  R "be:getPlayerVehicle(0):queueLuaCommand('input.event(\"throttle\",0) input.event(\"brake\",1)') return 1" > /dev/null
  nap 4
  N1="$(R "return carSurfaceFx_scratch and carSurfaceFx_scratch.count(be:getPlayerVehicleID(0)) or -1" | tr -d '\r')"
  if [ "${N1:-0}" -gt "${N0:-0}" ] 2>/dev/null; then rec "wall scrape leaves scratches" PASS "scratch marks $N0 -> $N1"; else rec "wall scrape leaves scratches" FAIL "scratch marks $N0 -> $N1 (no contact, or no hit report)"; fi
  cam external; nap 2; shot scratch_real
fi

dbg ""
cam driver
{
  echo "# Car Surface FX QA $(date '+%F %H:%M')"; echo
  echo "| check | result | evidence |"; echo "|---|---|---|"
  awk -F'\t' '{ gsub(/\|/, "/", $3); print "| " $1 " | " $2 " | " $3 " |" }' "$RESULTS"
} > "$HERE/last_report.md"
echo "report: $HERE/last_report.md, screenshots: $OUT/surfacefx_*.jpg"
grep -q $'\tFAIL\t' "$RESULTS" && exit 1
exit 0
