part of 'map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAP REPLAY CONTROLS
// ─────────────────────────────────────────────────────────────────────────────

extension _MapScreenReplayControls on _MapScreenState {
  Widget _buildReplayControls() {
    return ValueListenableBuilder<int>(
      valueListenable: _replayIndexNotifier,
      builder: (_, int index, __) {
        final int total = math.max(1, _route.validPoints.length);
        final double progress = total <= 1 ? 0.0 : index / (total - 1);
        final double replaySpeed = _speedAtReplayIndex(index);

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: _kBlue.withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBlue.withValues(alpha: 0.16)),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _PressableButton(
                    onTap: _replayPlaying ? _pauseReplay : _startReplay,
                    child: _ReplayRoundButton(
                      icon: _replayPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      color: _kBlueSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'TRIP REPLAY',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${index + 1}/$total · ${replaySpeed.toStringAsFixed(0)} km/h',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ReplaySpeedChip(
                    label: '${_replaySpeed.toStringAsFixed(0)}x',
                    onTap: () {
                      final double next = _replaySpeed == 1.0
                          ? 2.0
                          : _replaySpeed == 2.0
                              ? 4.0
                              : 1.0;
                      _setReplaySpeed(next);
                    },
                  ),
                  const SizedBox(width: 8),
                  _PressableButton(
                    onTap: _resetReplay,
                    child: const _ReplayRoundButton(
                      icon: CupertinoIcons.arrow_counterclockwise,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  activeColor: _kBlueSoft,
                  inactiveColor: Colors.white.withValues(alpha: 0.13),
                  onChanged: (double value) {
                    final int nextIndex =
                        (value * (total - 1)).round().clamp(0, total - 1);
                    _setReplayIndex(nextIndex, moveCamera: true);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
