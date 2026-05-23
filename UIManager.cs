using System.Collections.Generic;
using Godot;

public partial class UIManager : Control
{
	[Signal]
	public delegate void BPMChangedEventHandler(int bpm);

	[Signal]
	public delegate void TimeSignatureChangedEventHandler(int beats, int unit);

	[Signal]
	public delegate void VolumeChangedEventHandler(float volume);

	[Signal]
	public delegate void PlayToggledEventHandler(bool playing);

	[Signal]
	public delegate void SoundChangedEventHandler(int soundType);

	[Signal]
	public delegate void AccentModeChangedEventHandler(int mode);

	private HSlider _bpmSlider;
	private Label _bpmValueLabel;
	private OptionButton _timeSigButton;
	private OptionButton _soundButton;
	private OptionButton _accentButton;
	private HSlider _volumeSlider;
	private Label _volumeValueLabel;
	private Button _playButton;
	private HBoxContainer _beatDotsContainer;
	private List<ColorRect> _beatDots = new();
	private Label _timeSigDisplayLabel;

	private bool _isPlaying;
	private int _currentBeats = 4;
	private int _currentUnit = 4;

	private static readonly (string Label, int Beats, int Unit)[] TimeSignatures = {
		("2/4", 2, 4),
		("3/4", 3, 4),
		("4/4", 4, 4),
		("5/4", 5, 4),
		("6/8", 6, 8),
		("7/8", 7, 8),
	};

	private static readonly string[] SoundNames = { "Click", "Wood Block", "Beep" };
	private static readonly string[] AccentNames = { "Downbeat", "1st & 3rd", "All Even", "None" };

	private static readonly Color PanelBgColor = new(0.08f, 0.08f, 0.1f, 0.85f);
	private static readonly Color LabelColor = new(0.85f, 0.85f, 0.9f);
	private static readonly Color AccentColor = new(0.95f, 0.65f, 0.2f);
	private static readonly Color DimColor = new(0.25f, 0.25f, 0.3f);
	private static readonly Color PlayColor = new(0.2f, 0.7f, 0.3f);
	private static readonly Color PauseColor = new(0.85f, 0.65f, 0.2f);

	public override void _Ready()
	{
		SetAnchorsPreset(LayoutPreset.BottomWide);
		OffsetTop = -160;
		OffsetBottom = 0;
		OffsetLeft = 0;
		OffsetRight = 0;
		GrowVertical = GrowDirection.Begin;
		MouseFilter = MouseFilterEnum.Ignore;

		var panel = new Panel();
		panel.SetAnchorsPreset(LayoutPreset.FullRect);
		panel.MouseFilter = MouseFilterEnum.Stop;
		AddChild(panel);

		var style = new StyleBoxFlat();
		style.BgColor = PanelBgColor;
		style.CornerRadiusTopLeft = 12;
		style.CornerRadiusTopRight = 12;
		panel.AddThemeStyleboxOverride("panel", style);

		var margin = new MarginContainer();
		margin.SetAnchorsPreset(LayoutPreset.FullRect);
		margin.AddThemeConstantOverride("margin_left", 16);
		margin.AddThemeConstantOverride("margin_top", 10);
		margin.AddThemeConstantOverride("margin_right", 16);
		margin.AddThemeConstantOverride("margin_bottom", 10);
		panel.AddChild(margin);

		var vbox = new VBoxContainer();
		vbox.AddThemeConstantOverride("separation", 6);
		margin.AddChild(vbox);

		var row1 = new HBoxContainer();
		row1.AddThemeConstantOverride("separation", 12);
		vbox.AddChild(row1);

		var bpmLabelTitle = MakeLabel("BPM");
		row1.AddChild(bpmLabelTitle);

		_bpmSlider = new HSlider();
		_bpmSlider.MinValue = 20;
		_bpmSlider.MaxValue = 300;
		_bpmSlider.Value = 120;
		_bpmSlider.Step = 1;
		_bpmSlider.SizeFlagsHorizontal = SizeFlags.ExpandFill;
		_bpmSlider.ValueChanged += OnBPMSliderChanged;
		row1.AddChild(_bpmSlider);

		_bpmValueLabel = MakeLabel("120");
		_bpmValueLabel.CustomMinimumSize = new Vector2(36, 0);
		row1.AddChild(_bpmValueLabel);

		row1.AddChild(MakeLabel("Time"));
		_timeSigButton = new OptionButton();
		foreach (var ts in TimeSignatures)
		{
			_timeSigButton.AddItem(ts.Label);
		}

		_timeSigButton.Selected = 2;
		_timeSigButton.ItemSelected += OnTimeSigChanged;
		row1.AddChild(_timeSigButton);

		var row2 = new HBoxContainer();
		row2.AddThemeConstantOverride("separation", 12);
		vbox.AddChild(row2);

		row2.AddChild(MakeLabel("Sound"));
		_soundButton = new OptionButton();
		foreach (var s in SoundNames)
		{
			_soundButton.AddItem(s);
		}

		_soundButton.ItemSelected += OnSoundChanged;
		row2.AddChild(_soundButton);

		row2.AddChild(MakeLabel("Accent"));
		_accentButton = new OptionButton();
		foreach (var a in AccentNames)
		{
			_accentButton.AddItem(a);
		}

		_accentButton.ItemSelected += OnAccentChanged;
		row2.AddChild(_accentButton);

		row2.AddChild(MakeLabel("Vol"));
		_volumeSlider = new HSlider();
		_volumeSlider.MinValue = 0;
		_volumeSlider.MaxValue = 100;
		_volumeSlider.Value = 80;
		_volumeSlider.Step = 1;
		_volumeSlider.SizeFlagsHorizontal = SizeFlags.ExpandFill;
		_volumeSlider.ValueChanged += OnVolumeChanged;
		row2.AddChild(_volumeSlider);

		_volumeValueLabel = MakeLabel("80%");
		_volumeValueLabel.CustomMinimumSize = new Vector2(36, 0);
		row2.AddChild(_volumeValueLabel);

		var row3 = new HBoxContainer();
		row3.AddThemeConstantOverride("separation", 10);
		row3.Alignment = BoxContainer.AlignmentMode.Center;
		vbox.AddChild(row3);

		_playButton = new Button();
		_playButton.Text = "▶ Play";
		_playButton.CustomMinimumSize = new Vector2(100, 36);
		_playButton.Pressed += OnPlayPressed;
		row3.AddChild(_playButton);

		_beatDotsContainer = new HBoxContainer();
		_beatDotsContainer.Alignment = BoxContainer.AlignmentMode.Center;
		_beatDotsContainer.AddThemeConstantOverride("separation", 6);
		_beatDotsContainer.SizeFlagsHorizontal = SizeFlags.ExpandFill;
		row3.AddChild(_beatDotsContainer);

		_timeSigDisplayLabel = MakeLabel("4/4");
		_timeSigDisplayLabel.CustomMinimumSize = new Vector2(50, 0);
		row3.AddChild(_timeSigDisplayLabel);

		CreateBeatDots(4);
		UpdatePlayButtonStyle();
	}

	private Label MakeLabel(string text)
	{
		var label = new Label();
		label.Text = text;
		label.VerticalAlignment = VerticalAlignment.Center;
		label.AddThemeColorOverride("font_color", LabelColor);
		label.AddThemeFontSizeOverride("font_size", 14);
		return label;
	}

	private void CreateBeatDots(int count)
	{
		foreach (var dot in _beatDots)
		{
			dot.QueueFree();
		}

		_beatDots.Clear();

		for (int i = 0; i < count; i++)
		{
			var dot = new ColorRect();
			dot.CustomMinimumSize = new Vector2(18, 18);
			dot.Color = i == 0 ? AccentColor : DimColor;
			_beatDots.Add(dot);
			_beatDotsContainer.AddChild(dot);
		}
	}

	public void OnTick(int beat, int totalBeats)
	{
		for (int i = 0; i < _beatDots.Count; i++)
		{
			_beatDots[i].Color = (i == beat) ? AccentColor : DimColor;
		}
	}

	private void OnBPMSliderChanged(double value)
	{
		int bpm = (int)value;
		_bpmValueLabel.Text = bpm.ToString();
		EmitSignal(SignalName.BPMChanged, bpm);
	}

	private void OnTimeSigChanged(long index)
	{
		int idx = (int)index;
		if (idx < 0 || idx >= TimeSignatures.Length)
		{
			return;
		}

		var ts = TimeSignatures[idx];
		_currentBeats = ts.Beats;
		_currentUnit = ts.Unit;
		_timeSigDisplayLabel.Text = ts.Label;
		CreateBeatDots(ts.Beats);
		EmitSignal(SignalName.TimeSignatureChanged, ts.Beats, ts.Unit);
	}

	private void OnSoundChanged(long index)
	{
		EmitSignal(SignalName.SoundChanged, (int)index);
	}

	private void OnAccentChanged(long index)
	{
		EmitSignal(SignalName.AccentModeChanged, (int)index);
	}

	private void OnVolumeChanged(double value)
	{
		int pct = (int)value;
		_volumeValueLabel.Text = $"{pct}%";
		EmitSignal(SignalName.VolumeChanged, pct / 100f);
	}

	private void OnPlayPressed()
	{
		_isPlaying = !_isPlaying;
		_playButton.Text = _isPlaying ? "⏸ Pause" : "▶ Play";
		UpdatePlayButtonStyle();
		EmitSignal(SignalName.PlayToggled, _isPlaying);
	}

	private void UpdatePlayButtonStyle()
	{
		var sb = new StyleBoxFlat();
		sb.BgColor = _isPlaying ? PauseColor : PlayColor;
		sb.CornerRadiusBottomLeft = 6;
		sb.CornerRadiusBottomRight = 6;
		sb.CornerRadiusTopLeft = 6;
		sb.CornerRadiusTopRight = 6;
		_playButton.AddThemeStyleboxOverride("normal", sb);

		var sbH = new StyleBoxFlat();
		sbH.BgColor = _isPlaying
			? new Color(PauseColor.R * 0.8f, PauseColor.G * 0.8f, PauseColor.B * 0.8f)
			: new Color(PlayColor.R * 0.8f, PlayColor.G * 0.8f, PlayColor.B * 0.8f);
		sbH.CornerRadiusBottomLeft = 6;
		sbH.CornerRadiusBottomRight = 6;
		sbH.CornerRadiusTopLeft = 6;
		sbH.CornerRadiusTopRight = 6;
		_playButton.AddThemeStyleboxOverride("hover", sbH);
	}
}
