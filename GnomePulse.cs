using System;
using Godot;

public partial class GnomePulse : Node3D
{
	[Export]
	public float BaseBounceHeight { get; set; } = 0.25f;

	[Export]
	public float AccentBounceHeight { get; set; } = 0.55f;

	[Export]
	public double BounceDuration { get; set; } = 0.12;

	private Vector3 _originalPosition;
	private double _bounceTimer;
	private bool _isBouncing;
	private bool _isAccented;

	public override void _Ready()
	{
		_originalPosition = Position;
	}

	public void OnTick(bool isAccent)
	{
		_bounceTimer = 0.0;
		_isBouncing = true;
		_isAccented = isAccent;
	}

	public override void _Process(double delta)
	{
		if (!_isBouncing)
		{
			return;
		}

		_bounceTimer += delta;

		if (_bounceTimer >= BounceDuration)
		{
			_bounceTimer = BounceDuration;
			_isBouncing = false;
			Position = _originalPosition;
			return;
		}

		float t = (float)(_bounceTimer / BounceDuration);
		float height = Mathf.Sin(t * Mathf.Pi);
		float maxHeight = _isAccented ? AccentBounceHeight : BaseBounceHeight;

		Position = _originalPosition + Vector3.Up * height * maxHeight;
	}
}
