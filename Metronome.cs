using System;
using Godot;

public partial class Metronome : Node
{
	[Signal]
	public delegate void TickEventHandler(int beat, int totalBeats, bool isAccent);

	[Signal]
	public delegate void BeatChangedEventHandler(int beat);

	private int _bpm = 120;
	public int BPM
	{
		get => _bpm;
		set
		{
			_bpm = Mathf.Clamp(value, 20, 300);
			_tickInterval = 60.0 / _bpm;
		}
	}

	private int _beatsPerMeasure = 4;
	public int BeatsPerMeasure
	{
		get => _beatsPerMeasure;
		set
		{
			_beatsPerMeasure = Mathf.Clamp(value, 1, 16);
			_currentBeat = 0;
			_timeAccumulator = 0.0;
			AccentPattern = GeneratePattern(_beatsPerMeasure, _accentMode);
		}
	}

	private int _beatUnit = 4;
	public int BeatUnit
	{
		get => _beatUnit;
		set => _beatUnit = value;
	}

	public bool[] AccentPattern { get; private set; } = { true, false, false, false };

	private int _accentMode = 0;
	private int _currentBeat = 0;
	private double _timeAccumulator = 0.0;
	private double _tickInterval;
	private bool _isPlaying = false;

	public bool IsPlaying => _isPlaying;

	public override void _Ready()
	{
		_tickInterval = 60.0 / _bpm;
	}

	public void Play()
	{
		_isPlaying = true;
		_timeAccumulator = 0.0;
	}

	public void Pause()
	{
		_isPlaying = false;
	}

	public void Stop()
	{
		_isPlaying = false;
		_currentBeat = 0;
		_timeAccumulator = 0.0;
		EmitSignal(SignalName.BeatChanged, 0);
	}

	public void SetAccentMode(int mode)
	{
		_accentMode = mode;
		AccentPattern = GeneratePattern(_beatsPerMeasure, mode);
	}

	public void SetTimeSignature(int beats, int unit)
	{
		BeatsPerMeasure = beats;
		BeatUnit = unit;
	}

	private bool[] GeneratePattern(int beats, int mode)
	{
		var pattern = new bool[beats];
		switch (mode)
		{
			case 0:
				pattern[0] = true;
				break;
			case 1:
				pattern[0] = true;
				if (beats > 2)
				{
					pattern[2] = true;
				}

				break;
			case 2:
				for (int i = 0; i < beats; i += 2)
				{
					pattern[i] = true;
				}

				break;
			default:
				break;
		}
		return pattern;
	}

	public override void _Process(double delta)
	{
		if (!_isPlaying)
		{
			return;
		}

		_timeAccumulator += delta;

		if (_timeAccumulator >= _tickInterval)
		{
			_timeAccumulator -= _tickInterval;

			bool isAccent = _currentBeat < AccentPattern.Length && AccentPattern[_currentBeat];

			EmitSignal(SignalName.Tick, _currentBeat, _beatsPerMeasure, isAccent);
			EmitSignal(SignalName.BeatChanged, _currentBeat);

			_currentBeat = (_currentBeat + 1) % _beatsPerMeasure;
		}
	}
}
