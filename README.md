# Metrognome

A whimsical 3D metronome built in **Godot 4.6** with **GDScript**. A line of garden gnomes (or frogs, or beavers) stands in an enchanted mushroom grove and hops to the beat — one character per beat in the current time signature.

![screenshot placeholder](docs/screenshot.png)

## Play it in your browser

Deployed to GitHub Pages on every push to `main`.

## Features

### Metronome engine
- 20–300 BPM, time signatures 2/4 / 3/4 / 4/4 / 5/4 / 6/8 / 7/8
- Accent modes: Downbeat / 1st & 3rd / All Even / None
- **Tap Tempo** — open the drawer, tap "Tap Tempo", then tap anywhere on screen to set the BPM live; rolling 8-tap average, resets after 3 s of silence

### Characters & animation
- Three performers: **Gnome**, **Frog**, **Beaver** — each with a signature sound (pulse / ribbit / thump)
- Beat-synced skeletal hop animation; arms-down idle grafted from a separate clip
- One character per beat bouncing left-to-right down the line; larger hop on accented beats (`gnome_pulse.gd`)

### Enchanted grove
- Procedurally generated forest: 130+ background trees, mid-ring trees, bushes, ferns, mushroom clusters — placed with sightline-clearing, overlap avoidance, and per-asset pivot compensation
- Dancing mushrooms sway to the beat; self-illuminating caps glow brighter at night
- GPU particle fireflies drift over the grove when the metronome is playing
- **4-state time-of-day** (dawn / day / dusk / night) — auto-selected from the device clock on launch, or cycle manually via the icon in the top-right corner:
  - *Dawn* — purple sky, warm pink horizon, low east sun
  - *Day* — bright blue sky, warm overhead sun
  - *Dusk* — deep blue sky, fiery orange horizon, low west sun
  - *Night* — deep indigo sky, cool moonlight, glowing moon disc in the sky
- Procedural fog tint, glow intensity, firefly density, and mushroom emission all update per time-of-day

### Audio
- Procedural click synthesis via `AudioStreamGenerator` — exponentially-decaying sine bursts, no sample files needed for the metronome itself
- Per-character WAV vocalizations (gnome pulse, frog ribbit, beaver thump)
- iOS `AVAudioSession` Playback category set so audio plays with the silent switch on

### UI (`ui_manager.gd`)
- Always-visible bottom bar: Play/Pause, BPM ± steppers, BPM readout, beat dots
- Collapsible drawer: character selector, BPM fine-tune slider, time signature, sound type, accent mode, volume, Tap Tempo button
- Time-of-day icon overlay anchored to the top-right corner (cycles dawn → day → dusk → night)
- Tap Tempo full-screen overlay with giant live BPM readout, accent-gold flash on each tap
- Fully built in code with `Control` nodes and `StyleBoxFlat` theming — no external UI scenes
- Responsive layout scales for portrait phones, landscape tablets, and desktop

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
Main.tscn              # entry scene — root Node3D with main.gd attached
main.gd                # composition root: env, lighting, ground, characters,
                       #   forest, fireflies, animals, audio, UI, camera,
                       #   time-of-day palettes, moon mesh
metronome.gd           # BPM engine — emits tick/beat_changed signals
audio_clicker.gd       # procedural click synthesis + WAV character sounds
gnome_pulse.gd         # per-beat bounce node (sine-arc parabola)
mushroom_sway.gd       # dancing mushroom pivot controller
ui_manager.gd          # bottom HUD + collapsible drawer + tap tempo overlay
                       #   + top-right time-of-day icon (CanvasLayer 1)
assets/
  gnome/               # gnome GLBs (biped, hop, idle, icon)
  frog_biped/          # frog GLBs
  beaver_biped/        # beaver GLBs
  animals/             # frog.glb, opossum.glb (grove decoration)
  forest/              # tree, mushroom, fern, bush GLBs + grass texture
  branding/            # icon_1024.png, gnome_cutout.png, splash assets
  fonts/               # LuckiestGuy-Regular.ttf
  sounds/              # gnome_pulse.wav, frog_ribbit.wav, beaver_thump.wav
export_presets.cfg     # iOS, Android, Web, Windows, Linux export targets
```

## CI / Deploy

`.github/workflows/ci.yml` runs on every push and PR:

| Job | Trigger | What it does |
|-----|---------|--------------|
| `validate` | push + PR | Downloads Godot 4.6.2, imports assets, checks GDScript for parse errors |
| `export-web` | push to `main` | Exports to `build/web/index.html` |
| `deploy` | push to `main` | Deploys `build/web/` to GitHub Pages |
| `export-android` | push to `main` | Signs and exports AAB → Play Console internal track |

Enable GitHub Pages in **Settings → Pages → Source: GitHub Actions** to activate the deploy step.

## Contributing

See [AGENTS.md](AGENTS.md) for the conventions AI assistants and human contributors should follow.

## License

MIT. See [LICENSE](LICENSE).
