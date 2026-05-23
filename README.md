# metrognome

A whimsical 3D metronome built in **Godot 4.6** with **C#**. A garden gnome stands in a mushroom grove and bounces to the beat. Frogs hop in place; an opossum wanders the grove on a curvy path. Driven by a procedural audio click generator with selectable sound types, time signatures, and accent patterns.

![screenshot placeholder](docs/screenshot.png)

## Features

- Procedural metronome (`Metronome.cs`) — 20–300 BPM, time signatures 2/4 / 3/4 / 4/4 / 5/4 / 6/8 / 7/8.
- Procedural audio clicks (`AudioClicker.cs`) — three voice types (Click / Wood Block / Beep) generated as exponentially-decaying sine bursts via `AudioStreamGenerator`.
- Accent modes: Downbeat / 1st & 3rd / All Even / None.
- Gnome bounce (`GnomePulse.cs`) reacts to each tick; bigger bounce on accents.
- Mushroom grove placed procedurally with per-asset scale + pivot compensation, sightline-clearing rules, and overlap avoidance.
- Animated wildlife: frogs face the camera; the opossum walks a randomized curvy path while the metronome is playing.
- Bottom HUD (`UIManager.cs`) — fully built in code with `Control` nodes, `StyleBoxFlat` theming, and live beat dots.

## Requirements

- [Godot 4.6+ with .NET (Mono) support](https://godotengine.org/download)
- [.NET SDK 9.0](https://dotnet.microsoft.com/download)

## Run

```bash
dotnet build
godot --path . Main.tscn
# or on macOS:
/Applications/Godot_mono.app/Contents/MacOS/Godot --path .
```

## Project layout

```
Main.tscn          # entry scene — instantiates Main.cs
Main.cs            # composition root: env, lighting, ground, gnome, mushrooms, animals, audio, UI, camera
Metronome.cs       # ticks based on BPM/time signature, emits Tick / BeatChanged
AudioClicker.cs    # generates click + accent audio frames for the current sound type
GnomePulse.cs      # tweened bounce on each Tick
UIManager.cs       # bottom HUD: BPM slider, time-sig, sound, accent, volume, play, beat dots
assets/
  gnome/           # garden_gnome.glb
  mushrooms/       # mushroom.glb, amanita_muscaria_mushroom.glb, dancing_mushroom.glb
  animals/         # frog.glb, opossum.glb
```

## Development

```bash
dotnet build              # compile C#
dotnet format --verify-no-changes   # style check (CI)
dotnet format                       # auto-format
```

`Main.cs` is the only entry point; child scripts are wired up via signals in `SetupUI()` and `SetupMetronome()`.

## Contributing

See [AGENTS.md](AGENTS.md) for the conventions AI assistants should follow when editing this repo. The same conventions apply to human contributors.

## License

MIT. See [LICENSE](LICENSE).
