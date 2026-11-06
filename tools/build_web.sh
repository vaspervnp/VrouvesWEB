#!/bin/bash
# Export the web version with the Windows Godot 4.7.2 (it needs the web export templates)
# and pack it for GamePix: build/LetsGoForVrouves-gamepix.zip, with index.html at its root.
#   tools/build_web.sh
set -e
cd "$(dirname "$0")/.."
G="/mnt/c/Program Files/Godot/Godot_v4.7.2-stable_win64.exe"
P="$(wslpath -w "$PWD")"

rm -rf build/web
mkdir -p build/web
"$G" --headless --path "$P" --import >/dev/null 2>&1 || true
"$G" --headless --path "$P" --export-release "GamePix" build/web/index.html 2>&1 | grep -E "ERROR:|WARNING:" | tee build/web/errors.txt || true
if [ -s build/web/errors.txt ]; then exit 1; fi
rm build/web/errors.txt
test -f build/web/index.pck

# the picture behind the loading bar (web/shell.html)
ffmpeg -v error -y -i art/title.png -vf scale=1280:-2 -q:v 4 build/web/loading.jpg
# the boot splash Godot writes next to the page is not used
rm -f build/web/index.png

rm -f build/LetsGoForVrouves-gamepix.zip
(cd build/web && zip -q -9 -r ../LetsGoForVrouves-gamepix.zip .)
ls -l build/web build/LetsGoForVrouves-gamepix.zip
