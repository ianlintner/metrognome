# metrognome

A whimsical 3D metronome built in **Godot 4.6** with **GDScript**. A line of garden gnomes stands in a mushroom grove and bounces to the beat — one gnome per beat in the current time signature. Frogs face the camera; an opossum wanders the grove on a curvy path while the metronome is playing.

![screenshot placeholder](docs/screenshot.png)

## Play it in your browser

Deployed to GitHub Pages on every push to `main`.

## Features

- Procedural metronome (`metronome.gd`) — 20–300 BPM, time signatures 2/4 / 3/4 / 4/4 / 5/4 / 6/8 / 7/8.
- Procedural audio clicks (`audio_clicker.gd`) — three voice types (Click / Wood Block / Beep) generated as exponentially-decaying sine bursts via `AudioStreamGenerator`.
- Accent modes: Downbeat / 1st & 3rd / All Even / None.
- Dynamic gnome line (`gnome_pulse.gd`) — one gnome per beat, bouncing in order; larger bounce on accented beats.
- Mushroom grove placed procedurally with per-asset scale + pivot compensation, sightline-clearing rules, and overlap avoidance.
- Animated wildlife: frogs face the camera; the opossum walks a randomized curvy path while the metronome is playing.
- Bottom HUD (`ui_manager.gd`) — fully built in code with `Control` nodes, `StyleBoxFlat` theming, and live beat dots.

## Requirements

- [Godot 4.6+ (standard, **not** Mono)](https://godotengine.org/download)

No .NET SDK, no compiler, no build step — pure GDScript.

## Run

```bash
# macOS
/Applications/Godot.app/Contents/MacOS/Godot --path .

# Linux
godot --path .
```

Or open the project folder in the Godot editor and press **F5**.

## Project layout

```
Main.tscn          # entry scene — root Node3D with main.gd attached
main.gd            # composition root: env, lighting, ground, gnomes, mushrooms, animals, audio, UI, camera
metronome.gd       # ticks based on BPM/time signature, emits tick / beat_changed
audio_clicker.gd   # generates click + accent audio frames for the current sound type
gnome_pulse.gd     # sine-arc bounce on each tick
ui_manager.gd      # bottom HUD: BPM slider, time-sig, sound, accent, volume, play, beat dots
assets/
  gnome/           # garden_gnome.glb
  mushrooms/       # mushroom.glb, amanita_muscaria_mushroom.glb, dancing_mushroom.glb
  animals/         # frog.glb, opossum.glb
export_presets.cfg # Web export target → build/web/index.html
```

## CI / Deploy

`.github/workflows/ci.yml` runs on every push and PR:

| Job | Trigger | What it does |
| --- | --- | --- |
| `validate` | push + PR | Downloads Godot 4.6.2, imports assets, checks GDScript for parse errors |
| `export-web` | push to `main` | Downloads export templates, exports to `build/web/` |
| `deploy` | push to `main` | Deploys `build/web/` to GitHub Pages |

Enable GitHub Pages in **Settings → Pages → Source: GitHub Actions** to activate the deploy step.

## Contributing

See [AGENTS.md](AGENTS.md) for the conventions AI assistants and human contributors should follow.

## License

MIT. See [LICENSE](LICENSE).
