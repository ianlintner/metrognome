using System;
using System.Collections.Generic;
using Godot;

public partial class Main : Node3D
{
	private Metronome _metronome;
	private AudioClicker _audioClicker;
	private GnomePulse _gnomePulse;
	private UIManager _uiManager;

	private readonly System.Collections.Generic.List<(Vector2 Pos, float Radius)> _occupied = new();
	private readonly System.Collections.Generic.List<AnimationPlayer> _animPlayers = new();

	private Node3D _opossum;
	private Vector3 _opossumTarget;
	private float _opossumPhase;
	private readonly RandomNumberGenerator _opossumRng = new();

	private bool IsClear(float x, float z, float radius)
	{
		var p = new Vector2(x, z);
		foreach (var o in _occupied)
		{
			if (p.DistanceTo(o.Pos) < radius + o.Radius)
			{
				return false;
			}
		}
		return true;
	}

	public override void _Ready()
	{
		SetupEnvironment();
		SetupLighting();
		SetupGround();
		SetupGnome();
		SetupMushrooms();
		SetupAnimals();
		SetupAudio();
		SetupMetronome();
		SetupUI();
		SetupCamera();
	}

	private void SetupEnvironment()
	{
		var worldEnv = new WorldEnvironment();
		var env = new Godot.Environment();
		env.BackgroundMode = Godot.Environment.BGMode.Sky;
		env.AmbientLightSource = Godot.Environment.AmbientSource.Sky;
		env.AmbientLightColor = new Color(0.5f, 0.55f, 0.4f);
		env.AmbientLightEnergy = 0.7f;

		var skyMat = new ProceduralSkyMaterial();
		skyMat.SkyTopColor = new Color(0.35f, 0.55f, 0.85f);
		skyMat.SkyHorizonColor = new Color(0.6f, 0.7f, 0.75f);
		skyMat.GroundHorizonColor = new Color(0.25f, 0.35f, 0.15f);
		skyMat.GroundBottomColor = new Color(0.1f, 0.2f, 0.05f);

		var sky = new Sky();
		sky.SkyMaterial = skyMat;
		env.Sky = sky;

		env.SsaoEnabled = true;
		env.SsilEnabled = true;

		worldEnv.Environment = env;
		AddChild(worldEnv);
	}

	private void SetupLighting()
	{
		var sun = new DirectionalLight3D();
		sun.Name = "Sun";
		sun.RotationDegrees = new Vector3(-50, 30, 0);
		sun.LightEnergy = 1.8f;
		sun.LightColor = new Color(1f, 0.95f, 0.85f);
		sun.ShadowEnabled = true;
		sun.DirectionalShadowMode = DirectionalLight3D.ShadowMode.Parallel2Splits;
		sun.DirectionalShadowSplit1 = 0.1f;
		sun.DirectionalShadowSplit2 = 0.3f;
		AddChild(sun);
	}

	private void SetupGround()
	{
		var groundMesh = new PlaneMesh();
		groundMesh.Size = new Vector2(80, 80);

		var ground = new MeshInstance3D();
		ground.Name = "Ground";
		ground.Mesh = groundMesh;

		var mat = new StandardMaterial3D();
		mat.AlbedoColor = new Color(0.12f, 0.28f, 0.08f);
		mat.Roughness = 0.9f;
		ground.MaterialOverride = mat;
		ground.CreateTrimeshCollision();

		AddChild(ground);
	}

	private void SetupGnome()
	{
		_gnomePulse = new GnomePulse();
		_gnomePulse.Name = "GnomeRoot";
		_gnomePulse.Position = new Vector3(0, 1.5f, 0);
		_gnomePulse.BaseBounceHeight = 0.25f;
		_gnomePulse.AccentBounceHeight = 0.55f;
		AddChild(_gnomePulse);

		var gnomeScene = GD.Load<PackedScene>("res://assets/gnome/garden_gnome.glb");
		if (gnomeScene != null)
		{
			var gnomeModel = gnomeScene.Instantiate<Node3D>();
			gnomeModel.Name = "GnomeModel";
			gnomeModel.Scale = new Vector3(1.5f, 1.5f, 1.5f);
			_gnomePulse.AddChild(gnomeModel);
		}
		else
		{
			GD.PrintErr("Failed to load gnome model from res://assets/gnome/garden_gnome.glb");
		}
	}

	private void SetupMushrooms()
	{
		var forest = new Node3D();
		forest.Name = "MushroomForest";
		AddChild(forest);

		var rng = new RandomNumberGenerator();
		rng.Seed = 42;

		// Skip the big mushrooms.glb cluster — its rock base + giant mushrooms
		// keep blocking the camera no matter where it's placed.
		// amanita_muscaria_mushroom.glb has a native scale that's ~10x bigger
		// than the other two — give it a much smaller multiplier so it renders
		// at a comparable height.
		var kinds = new (string Path, float ScaleMin, float ScaleMax, float YOffset)[] {
			("res://assets/mushrooms/mushroom.glb",                  0.6f, 3.6f,  0.5f),
			("res://assets/mushrooms/amanita_muscaria_mushroom.glb", 0.084f, 0.504f, -0.5f),
			("res://assets/mushrooms/dancing_mushroom.glb",          0.6f, 3.6f, -0.1f),
		};
		var loaded = new System.Collections.Generic.List<(PackedScene Scene, float Min, float Max, string Path, float Y)>();
		foreach (var k in kinds)
		{
			var s = GD.Load<PackedScene>(k.Path);
			if (s != null)
			{
				loaded.Add((s, k.ScaleMin, k.ScaleMax, k.Path, k.YOffset));
			}
		}
		if (loaded.Count == 0)
		{
			return;
		}

		// Reserve a circle around the gnome so nothing crowds it.
		_occupied.Add((Vector2.Zero, 2.5f));

		// Keep a clear sightline from the camera (z=-14) through the gnome (z=0)
		// and create a grove-opening effect by pushing mushrooms behind the
		// gnome further back than mushrooms on the sides.
		const int count = 22;
		int placed = 0;
		int attempts = 0;
		while (placed < count && attempts < count * 30)
		{
			attempts++;
			float angle = rng.RandfRange(0f, Mathf.Tau);
			float dist = rng.RandfRange(9f, 22f);
			float x = Mathf.Cos(angle) * dist;
			float z = Mathf.Sin(angle) * dist;

			// Reject a corridor down the camera→gnome sightline.
			if (Mathf.Abs(x) < 3.5f && z < 3f)
			{
				continue;
			}
			// Anything in the front half (toward camera) must stay well to the side.
			if (z < 0f && Mathf.Abs(x) < 8f)
			{
				continue;
			}
			// Behind the gnome: push further back to open the grove.
			if (z > 0f && dist < 14f)
			{
				continue;
			}

			var entry = loaded[placed % loaded.Count];
			float scale = rng.RandfRange(entry.Min, entry.Max);
			// Approximate footprint radius — mushroom kinds are ~1.2m radius at
			// scale 1.0; amanita's small scale is intentional and lands ~0.8m.
			float radius = entry.Path.Contains("amanita") ? scale * 8f : scale * 1.2f;
			if (!IsClear(x, z, radius + 0.3f))
			{
				continue;
			}

			placed++;
			_occupied.Add((new Vector2(x, z), radius));

			var mushroom = entry.Scene.Instantiate<Node3D>();
			// mushroom.glb's pivot sits in the middle of the cap, so the bigger
			// it scales the more its base sinks — multiply its Y by scale so the
			// stem stays planted on the ground regardless of size.
			float y = entry.Path.Contains("dancing")
				? entry.Y * scale
				: (entry.Path.Contains("mushroom.glb") && !entry.Path.Contains("mushrooms.glb")
					? entry.Y + 0.6f * (scale - 1f) + 0.15f * (scale - 1f) * (scale - 1f)
					: entry.Y);
			mushroom.Position = new Vector3(x, y, z);
			mushroom.Scale = new Vector3(scale, scale, scale);
			mushroom.RotateY(rng.RandfRange(0f, Mathf.Tau));
			forest.AddChild(mushroom);

			PlayFirstAnimation(mushroom);
		}

		// A few extra-large hero mushrooms — restricted to BEHIND the gnome so
		// they never block the camera's view of the foreground.
		const int giantCount = 6;
		int giantsPlaced = 0;
		int giantAttempts = 0;
		while (giantsPlaced < giantCount && giantAttempts < giantCount * 40)
		{
			giantAttempts++;
			// Back hemisphere only: z >= 0
			float angle = rng.RandfRange(0.1f, Mathf.Pi - 0.1f);
			float dist = rng.RandfRange(14f, 26f);
			float x = Mathf.Cos(angle) * dist;
			float z = Mathf.Sin(angle) * dist;

			var entry = loaded[rng.RandiRange(0, loaded.Count - 1)];
			float scale = rng.RandfRange(entry.Max, entry.Max * 3f);
			float radius = entry.Path.Contains("amanita") ? scale * 8f : scale * 1.2f;
			if (!IsClear(x, z, radius + 0.5f))
			{
				continue;
			}

			_occupied.Add((new Vector2(x, z), radius));

			var giant = entry.Scene.Instantiate<Node3D>();
			float giantY = entry.Path.Contains("dancing")
				? entry.Y * scale
				: (entry.Path.Contains("mushroom.glb") && !entry.Path.Contains("mushrooms.glb")
					? entry.Y * scale + scale * 0.48f
					: entry.Y + scale * 0.48f);
			giant.Position = new Vector3(x, giantY, z);
			giant.Scale = new Vector3(scale, scale, scale);
			giant.RotateY(rng.RandfRange(0f, Mathf.Tau));
			forest.AddChild(giant);

			PlayFirstAnimation(giant);
			giantsPlaced++;
		}

		// Distant horizon mushrooms — far back, lots of them, to suggest depth.
		const int horizonCount = 18;
		int horizonPlaced = 0;
		int horizonAttempts = 0;
		while (horizonPlaced < horizonCount && horizonAttempts < horizonCount * 30)
		{
			horizonAttempts++;
			// Back arc only, far out near the world edge.
			float angle = rng.RandfRange(-0.15f, Mathf.Pi + 0.15f);
			float dist = rng.RandfRange(24f, 30f);
			float x = Mathf.Cos(angle) * dist;
			float z = Mathf.Sin(angle) * dist;

			var entry = loaded[horizonPlaced % loaded.Count];
			float scale = rng.RandfRange(entry.Min, entry.Max);
			float radius = entry.Path.Contains("amanita") ? scale * 8f : scale * 1.2f;
			if (!IsClear(x, z, radius + 0.3f))
			{
				continue;
			}

			_occupied.Add((new Vector2(x, z), radius));

			var distant = entry.Scene.Instantiate<Node3D>();
			float dy = entry.Path.Contains("dancing")
				? entry.Y * scale
				: (entry.Path.Contains("mushroom.glb") && !entry.Path.Contains("mushrooms.glb")
					? entry.Y + 0.6f * (scale - 1f) + 0.15f * (scale - 1f) * (scale - 1f)
					: entry.Y);
			distant.Position = new Vector3(x, dy, z);
			distant.Scale = new Vector3(scale, scale, scale);
			distant.RotateY(rng.RandfRange(0f, Mathf.Tau));
			forest.AddChild(distant);

			PlayFirstAnimation(distant);
			horizonPlaced++;
		}
	}

	private void SetupAnimals()
	{
		var animals = new Node3D();
		animals.Name = "Animals";
		AddChild(animals);

		var rng = new RandomNumberGenerator();
		rng.Seed = 99;

		var frogScene = GD.Load<PackedScene>("res://assets/animals/frog.glb");
		var opossumScene = GD.Load<PackedScene>("res://assets/animals/opossum.glb");

		if (frogScene != null)
		{
			int frogCount = rng.RandiRange(3, 6);
			int spawned = 0, tries = 0;
			while (spawned < frogCount && tries < frogCount * 40)
			{
				tries++;
				float angle = rng.RandfRange(0f, Mathf.Tau);
				float dist = rng.RandfRange(3.5f, 8f);
				float x = Mathf.Cos(angle) * dist;
				float z = Mathf.Sin(angle) * dist;
				if (!IsClear(x, z, 1.8f))
				{
					continue;
				}

				_occupied.Add((new Vector2(x, z), 1.8f));

				var frog = frogScene.Instantiate<Node3D>();
				frog.Position = new Vector3(x, -0.67f, z);
				frog.Scale = Vector3.One * 3f;
				var cam = new Vector3(0f, frog.Position.Y, -14f);
				if ((cam - frog.Position).LengthSquared() > 0.0001f)
				{
					frog.LookAt(cam, Vector3.Up);
					frog.RotateObjectLocal(Vector3.Up, Mathf.Pi);
					frog.RotateObjectLocal(Vector3.Up, rng.RandfRange(-0.35f, 0.35f));
				}
				animals.AddChild(frog);
				PlayFirstAnimation(frog);
				spawned++;
			}
		}

		if (opossumScene != null)
		{
			float angle = 0f, dist = 6f, x = 0f, z = 0f;
			for (int t = 0; t < 30; t++)
			{
				angle = rng.RandfRange(0f, Mathf.Tau);
				dist = rng.RandfRange(5f, 7.5f);
				x = Mathf.Cos(angle) * dist;
				z = Mathf.Sin(angle) * dist;
				if (IsClear(x, z, 0.8f))
				{
					break;
				}
			}
			_occupied.Add((new Vector2(x, z), 0.8f));

			var opossum = opossumScene.Instantiate<Node3D>();
			opossum.Position = new Vector3(x, -0.08f, z);
			opossum.Scale = Vector3.One * 0.4f;
			opossum.RotateY(rng.RandfRange(0f, Mathf.Tau));
			animals.AddChild(opossum);
			PlayFirstAnimation(opossum);

			_opossum = opossum;
			_opossumRng.Seed = 1337;
			PickOpossumTarget();
		}
	}

	private void PickOpossumTarget()
	{
		for (int t = 0; t < 25; t++)
		{
			float a = _opossumRng.RandfRange(0f, Mathf.Tau);
			float d = _opossumRng.RandfRange(5f, 14f);
			float x = Mathf.Cos(a) * d;
			float z = Mathf.Sin(a) * d;
			if (Mathf.Sqrt(x * x + z * z) < 4f)
			{
				continue;
			}

			_opossumTarget = new Vector3(x, _opossum.Position.Y, z);
			return;
		}
		_opossumTarget = new Vector3(8f, _opossum.Position.Y, 8f);
	}

	public override void _Process(double delta)
	{
		if (_opossum == null || _metronome == null || !_metronome.IsPlaying)
		{
			return;
		}

		var pos = _opossum.Position;
		var toTarget = _opossumTarget - pos;
		toTarget.Y = 0f;

		if (toTarget.Length() < 0.5f)
		{
			PickOpossumTarget();
			return;
		}

		var dir = toTarget.Normalized();
		_opossumPhase += (float)delta * 0.7f;
		float curve = Mathf.Sin(_opossumPhase) * 0.35f;
		var heading = dir.Rotated(Vector3.Up, curve);

		float speed = 1.1f;
		var step = heading * speed * (float)delta;
		var newPos = pos + step;
		_opossum.Position = new Vector3(newPos.X, pos.Y, newPos.Z);

		var look = _opossum.Position + heading;
		if ((look - _opossum.Position).LengthSquared() > 0.0001f)
		{
			_opossum.LookAt(look, Vector3.Up);
			_opossum.RotateObjectLocal(Vector3.Up, Mathf.Pi);
		}
	}

	private void PlayFirstAnimation(Node root)
	{
		var anim = FindAnimationPlayer(root);
		if (anim != null && anim.GetAnimationList().Length > 0)
		{
			var name = anim.GetAnimationList()[0];
			var a = anim.GetAnimation(name);
			if (a != null)
			{
				a.LoopMode = Animation.LoopModeEnum.Linear;
			}

			anim.Play(name);
			anim.Pause();
			_animPlayers.Add(anim);
		}
	}

	private AnimationPlayer FindAnimationPlayer(Node node)
	{
		if (node is AnimationPlayer ap)
		{
			return ap;
		}

		foreach (var child in node.GetChildren())
		{
			var found = FindAnimationPlayer(child);
			if (found != null)
			{
				return found;
			}
		}
		return null;
	}

	private void SetupAudio()
	{
		_audioClicker = new AudioClicker();
		_audioClicker.Name = "AudioClicker";
		AddChild(_audioClicker);
	}

	private void SetupMetronome()
	{
		_metronome = new Metronome();
		_metronome.Name = "Metronome";
		_metronome.BPM = 120;
		_metronome.BeatsPerMeasure = 4;
		AddChild(_metronome);
	}

	private void SetupUI()
	{
		var canvasLayer = new CanvasLayer();
		canvasLayer.Name = "UICanvasLayer";
		AddChild(canvasLayer);

		_uiManager = new UIManager();
		_uiManager.Name = "UI";
		canvasLayer.AddChild(_uiManager);

		_uiManager.BPMChanged += bpm => _metronome.BPM = bpm;
		_uiManager.TimeSignatureChanged += (beats, unit) => _metronome.SetTimeSignature(beats, unit);
		_uiManager.VolumeChanged += vol => _audioClicker.Volume = vol;
		_uiManager.SoundChanged += type => _audioClicker.SetSoundType(type);
		_uiManager.AccentModeChanged += mode => _metronome.SetAccentMode(mode);
		_uiManager.PlayToggled += playing =>
		{
			if (playing)
			{
				_metronome.Play();
			}
			else
			{
				_metronome.Pause();
			}

			foreach (var ap in _animPlayers)
			{
				if (playing)
				{
					ap.Play();
				}
				else
				{
					ap.Pause();
				}
			}
		};

		_metronome.Tick += (beat, total, isAccent) =>
		{
			if (isAccent)
			{
				_audioClicker.PlayAccent();
			}
			else
			{
				_audioClicker.PlayClick();
			}

			_gnomePulse.OnTick(isAccent);
			_uiManager.OnTick(beat, total);
		};
	}

	private void SetupCamera()
	{
		var camera = new Camera3D();
		camera.Name = "Camera3D";
		camera.Fov = 70f;
		AddChild(camera);
		camera.Position = new Vector3(0f, 5.0f, -14f);
		camera.LookAt(new Vector3(0, 1.4f, 0));

		var gnomeModel = _gnomePulse.GetNodeOrNull<Node3D>("GnomeModel");
		if (gnomeModel != null)
		{
			var targetXZ = new Vector3(camera.GlobalPosition.X, gnomeModel.GlobalPosition.Y, camera.GlobalPosition.Z);
			gnomeModel.LookAt(targetXZ, Vector3.Up);
			gnomeModel.RotateObjectLocal(Vector3.Up, -Mathf.Pi / 2f);
		}
	}
}
