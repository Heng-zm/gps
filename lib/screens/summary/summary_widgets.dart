part of 'summary_screen.dart';

// UX pass: summary widgets keep expensive route/stat calculations outside build
// and use App* shared components for consistent spacing, colors, and motion.

class _SummaryHeroRedesign extends StatelessWidget {
  static String _heroDateLabel(DateTime date) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final int monthIndex = date.month.clamp(1, 12).toInt() - 1;
    final String month = months[monthIndex];
    final String hour = date.hour.toString().padLeft(2, '0');
    final String minute = date.minute.toString().padLeft(2, '0');

    return '$month ${date.day}, ${date.year} · $hour:$minute';
  }

  const _SummaryHeroRedesign({
    required this.distance,
    required this.distanceUnit,
    required this.duration,
    required this.date,
    required this.quality,
  });

  final double distance;
  final String distanceUnit;
  final String duration;
  final DateTime date;
  final _RouteQualitySnapshot quality;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.blueButtonGradient,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kBlue.withValues(alpha: 0.32),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.location_north_line_fill,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Trip completed',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _heroDateLabel(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              AppStatusPill(
                label: '${quality.score}%',
                color: quality.color,
                icon: CupertinoIcons.checkmark_shield_fill,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Flexible(
                child: Text(
                  distance.toStringAsFixed(distance >= 100 ? 0 : 2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    height: 0.92,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -3.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  distanceUnit,
                  style: const TextStyle(
                    color: _kGoldSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              AppStatusPill(
                label: duration,
                color: _kTeal,
                icon: CupertinoIcons.timer,
              ),
              AppStatusPill(
                label: quality.accuracyLabel,
                color: quality.color,
                icon: CupertinoIcons.scope,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryEmptyNote extends StatelessWidget {
  const _SummaryEmptyNote({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      shadow: false,
      child: Row(
        children: <Widget>[
          const Icon(
            CupertinoIcons.info_circle_fill,
            color: Colors.white38,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _OfflineSyncCard extends StatelessWidget {
  const _OfflineSyncCard({
    required this.pendingCount,
    required this.onSync,
  });

  final ValueNotifier<int> pendingCount;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: pendingCount,
      builder: (_, int count, __) {
        if (count <= 0) return const SizedBox.shrink();

        return _GlassCard(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _kGold.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.arrow_2_circlepath,
                  color: _kGold,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const _SafeText(
                      'OFFLINE SYNC QUEUE',
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _SafeText(
                      '$count trip${count == 1 ? '' : 's'} waiting for cloud sync',
                      maxLines: 2,
                      softWrap: true,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _MiniSyncButton(onTap: onSync),
            ],
          ),
        );
      },
    );
  }
}

class _MiniSyncButton extends StatelessWidget {
  const _MiniSyncButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: _kGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _kGold.withValues(alpha: 0.18),
          ),
        ),
        child: const _SafeText(
          'SYNC',
          maxLines: 1,
          style: TextStyle(
            color: _kGold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}

class _RouteInsightStrip extends StatelessWidget {
  const _RouteInsightStrip({
    required this.distance,
    required this.avgSpeed,
    required this.pointCount,
    required this.speedUnit,
    required this.distanceUnit,
    required this.quality,
  });

  final double distance;
  final double avgSpeed;
  final int pointCount;
  final String speedUnit;
  final String distanceUnit;
  final _RouteQualitySnapshot quality;

  @override
  Widget build(BuildContext context) {
    final String message = pointCount < 3
        ? 'Route data is limited. Longer trips will produce better insights.'
        : '${quality.label} route quality · $pointCount points over '
            '${distance.toStringAsFixed(1)} $distanceUnit at '
            '${avgSpeed.toStringAsFixed(0)} $speedUnit average.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kTeal.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _kTeal.withValues(alpha: 0.13)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.sparkles, color: _kTeal, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: _SafeText(
              message,
              maxLines: 3,
              softWrap: true,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiFab extends StatelessWidget {
  const _AiFab({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      elevation: 12,
      onPressed: onTap,
      backgroundColor: _kPurple,
      icon: const Icon(
        Icons.auto_awesome,
        color: Colors.white,
        size: 18,
      ),
      label: const _SafeText(
        'ASK AI',
        maxLines: 1,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.borderColor = _kBorder,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.075),
            Colors.white.withValues(alpha: 0.035),
            Colors.white.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        color: _kCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
    this.textAlign,
    this.softWrap = false,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: softWrap,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
