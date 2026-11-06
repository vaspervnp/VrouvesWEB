# LET'S GO FOR VROUVES / ΠΑΜΕ ΓΙΑ ΒΡΟΥΒΕΣ (web, for GamePix)

The browser version of the cute Cretan tower defence, made to be published on
[GamePix](https://partners.gamepix.com/). It is the Godot 4.7 game of `../VrouvesPC` (the
same seven stages, defenders, invaders and rules), exported for the web and wired to the
GamePix SDK v3.

## What is different from the PC version

* **GamePix SDK** (`scripts/gpx.gd`, `web/shell.html`). The page loads
  `gamepix.sdk.js` before the engine, with the manual lifecycle:
  * the loading bar reports `lifecycle.loading()`;
  * the title screen calls `lifecycle.loaded()`, and the first Start calls `gameStart()`;
  * an interstitial ad plays after every stage that is won or lost. The SDK pauses the
    game around it;
  * a won stage reports `happyMoment("level_complete")`, and a lost one reports
    `sadMoment("level_failed" / "game_over")`. The game also sends `updateLevel` and
    `updateScore`.
* **Pause.** The SDK's `pause` / `resume` events and a hidden browser tab stop the whole
  game and mute every sound.
* **Language.** The first time, it is `GamePix.lang()` (Greek for `el`, English
  otherwise). After that, it is the player's own choice.
* **Saving.** Settings and high scores go to `localStorage` (keys `vrouves_settings`,
  `vrouves_hiscores`), which the GamePix player keeps for the player. Off the web they are
  files in `user://`.
* **Touch.** Every control works with a tap:
  * choose a defender in the bottom bar, then tap a tile to build;
  * tap a defender once to see what it sells for, and tap it again within three seconds
    to sell it;
  * the pause box has Continue and Back to the title buttons;
  * the high-score name has an on-screen keyboard.
  Keys and the mouse work as on the PC.
* **No Quit or Full screen items** in the menu, as GamePix asks; the GamePix player has
  its own full screen. There are no links of any kind.
* **Engine.** It is the single-threaded web export, so it needs no SharedArrayBuffer or
  COOP/COEP headers, and it scales to any page size, landscape or portrait.

## Building

The export needs the Windows Godot 4.7.2 and its export templates (`web_nothreads_release`):

```bash
tools/build_web.sh
```

It writes `build/web/` (`index.html`, `index.js`, `index.wasm`, `index.pck`, the audio
worklets, the icons and `loading.jpg`, the picture behind the loading bar) and
`build/LetsGoForVrouves-gamepix.zip`, with `index.html` at its root, ready to upload. The
build stops on any script error.

## Trying it

Serve the build and open it with GamePix's local inspector, which mocks the ads:

```bash
python3 -m http.server 8060 --directory build/web
```

Then open `http://localhost:8060/?gpx_inspector=1&gpx_ad=success`.

The browser needs WebGL 2. `tools/webtest.py` (Windows python, standard library only)
drives a headless Edge through the DevTools protocol. It loads the page, clicks or taps,
and takes screenshots; the steps are in the file.

Developer arguments work as on the PC (`--stage N --bot`, `--ending SCORE`, `--lang gr`,
`--funds N`). On the web they go in the `"args"` of `GODOT_CONFIG` in a copy of
`index.html`, after a `"--"`.

## Uploading to GamePix

On the partner dashboard, upload `build/LetsGoForVrouves-gamepix.zip`. Use
`art/icon_512.png` / `art/icon_1024.png` for the icon and `art/title.png` for the cover;
both match the game's title. Test it in the GamePix testkit before publishing.
