part of 'map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAP REPLAY CONTROLS — compact, no App* dependency
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
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            color: _kBlue.withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBlue.withValues(alpha: 0.16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Semantics(
                    button: true,
                    label: _replayPlaying ? 'Pause replay' : 'Start replay',
                    child: _PressableButton(
                      onTap: _replayPlaying ? _pauseReplay : _startReplay,
                      child: _ReplayRoundButton(
                        icon: _replayPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: _kBlueSoft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReplayInfoText(
                      index: index,
                      total: total,
                      replaySpeed: replaySpeed,
                    ),
                  ),
                  _ReplaySpeedChip(
                    label: _replayCameraMode.label,
                    onTap: _cycleReplayCameraMode,
                  ),
                  const SizedBox(width: 7),
                  _ReplaySpeedChip(
                    label: '${_replaySpeed.toStringAsFixed(_replaySpeed == 0.5 ? 1 : 0)}x',
                    onTap: () {
                      final double next = _replaySpeed == 0.5
                          ? 1.0
                          : _replaySpeed == 1.0
                              ? 2.0
                              : _replaySpeed == 2.0
                                  ? 4.0
                                  : 0.5;
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
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0).toDouble(),
                  min: 0.0,
                  max: 1.0,
                  activeColor: _kBlueSoft,
                  inactiveColor: Colors.white.withValues(alpha: 0.13),
                  onChanged: (double value) {
                    final int nextIndex =
                        (value * (total - 1)).round().clamp(0, total - 1).toInt();
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

class _ReplayInfoText extends StatelessWidget {
  const _ReplayInfoText({
    required this.index,
    required this.total,
    required this.replaySpeed,
  });

  final int index;
  final int total;
  final double replaySpeed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'TRIP REPLAY',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
