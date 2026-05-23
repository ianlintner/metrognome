using System;
using Godot;

public partial class AudioClicker : Node
{
	private AudioStreamPlayer _player;
	private float _volume = 0.8f;
	public float Volume
	{
		get => _volume;
		set
		{
			_volume = Mathf.Clamp(value, 0f, 1f);
			if (_player != null)
			{
				_player.VolumeDb = Mathf.LinearToDb(_volume);
			}
		}
	}

	private Vector2[] _clickFrames;
	private Vector2[] _accentFrames;
	private bool _isPlaying;
	private Vector2[] _currentFrames;
	private int _currentFrame;
	private AudioStreamGeneratorPlayback _playback;
	private int _sampleRate = 44100;

	public override void _Ready()
	{
		_player = new AudioStreamPlayer();
		_player.Bus = "Master";
		AddChild(_player);
		GenerateSounds(0);
		Volume = _volume;
	}

	public void SetSoundType(int type)
	{
		GenerateSounds(type);
	}

	public void PlayClick()
	{
		StartPlayback(_clickFrames);
	}

	public void PlayAccent()
	{
		StartPlayback(_accentFrames);
	}

	private void StartPlayback(Vector2[] frames)
	{
		if (frames == null || frames.Length == 0)
		{
			return;
		}

		_player.Stop();

		var generator = new AudioStreamGenerator();
		generator.MixRate = _sampleRate;
		generator.BufferLength = 0.15f;

		_player.Stream = generator;
		_player.Play();

		_playback = (AudioStreamGeneratorPlayback)_player.GetStreamPlayback();
		_currentFrames = frames;
		_currentFrame = 0;
		_isPlaying = true;
	}

	public override void _Process(double delta)
	{
		if (!_isPlaying || _playback == null)
		{
			return;
		}

		int pushed = 0;
		int maxPerFrame = 200;

		while (_currentFrame < _currentFrames.Length && pushed < maxPerFrame)
		{
			if (_playback.CanPushBuffer(1))
			{
				_playback.PushFrame(_currentFrames[_currentFrame]);
				_currentFrame++;
				pushed++;
			}
			else
			{
				break;
			}
		}

		if (_currentFrame >= _currentFrames.Length)
		{
			_isPlaying = false;
		}
	}

	private void GenerateSounds(int type)
	{
		switch (type)
		{
			case 0:
				_clickFrames = GenerateFrames(1200f, 0.025f, 0.6f);
				_accentFrames = GenerateFrames(1600f, 0.035f, 0.8f);
				break;
			case 1:
				_clickFrames = GenerateFrames(500f, 0.04f, 0.7f);
				_accentFrames = GenerateFrames(700f, 0.05f, 0.9f);
				break;
			case 2:
				_clickFrames = GenerateFrames(900f, 0.02f, 0.5f);
				_accentFrames = GenerateFrames(1300f, 0.03f, 0.7f);
				break;
		}
	}

	private Vector2[] GenerateFrames(float frequency, float duration, float amplitude)
	{
		int totalFrames = (int)(_sampleRate * duration);
		var frames = new Vector2[totalFrames];

		for (int i = 0; i < totalFrames; i++)
		{
			float t = (float)i / _sampleRate;
			float envelope = Mathf.Exp(-t * 50f);
			float value = Mathf.Sin(2f * Mathf.Pi * frequency * t) * envelope * amplitude;
			frames[i] = new Vector2(value, value);
		}

		return frames;
	}
}
