import 'package:flutter/cupertino.dart';

import '../../design/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_action_button.dart';
import '../../widgets/common/app_filter_chip.dart';
import '../../widgets/common/app_glass_card.dart';
import '../../widgets/common/app_page_shell.dart';
import '../../widgets/common/app_status_pill.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.onFinish,
  });

  final VoidCallback? onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;
  String _unit = 'kmh';
  String _batteryMode = 'balanced';

  static const List<_OnboardingPageData> _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: CupertinoIcons.location_north_line_fill,
      title: 'Track smarter',
      subtitle:
          'Record routes, speed, distance, stops and trip quality with a clean live map.',
    ),
    _OnboardingPageData(
      icon: CupertinoIcons.map_fill,
      title: 'Plan with Mapbox',
      subtitle:
          'Search destinations, plan routes, preview distance and replay every trip later.',
    ),
    _OnboardingPageData(
      icon: CupertinoIcons.battery_25,
      title: 'Choose your setup',
      subtitle:
          'Pick your unit and battery mode. You can change everything later in Settings.',
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

  Future<void> _next() async {
    if (_isLast) {
      widget.onFinish?.call();
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    await _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageShell(
      title: 'Welcome',
      subtitle: 'Premium GPS tracker setup',
      trailing: AppStatusPill(
        label: '${_index + 1}/${_pages.length}',
        color: AppColors.blueSoft,
        icon: CupertinoIcons.sparkles,
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (int value) => setState(() => _index = value),
              itemBuilder: (BuildContext context, int index) {
                final _OnboardingPageData page = _pages[index];

                return AppFadeSlide(
                  key: ValueKey<int>(index),
                  child: _OnboardingPage(
                    data: page,
                    showSetup: index == 2,
                    unit: _unit,
                    batteryMode: _batteryMode,
                    onUnitChanged: (String value) => setState(() => _unit = value),
                    onBatteryModeChanged: (String value) {
                      setState(() => _batteryMode = value);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _Dots(count: _pages.length, index: _index),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: AppActionButton(
                  label: 'Skip',
                  icon: CupertinoIcons.forward_fill,
                  onTap: () {
                    widget.onFinish?.call();
                    Navigator.of(context).maybePop();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: AppActionButton(
                  label: _isLast ? 'Start using app' : 'Continue',
                  icon: _isLast
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.arrow_right_circle_fill,
                  primary: true,
                  onTap: _next,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.showSetup,
    required this.unit,
    required this.batteryMode,
    required this.onUnitChanged,
    required this.onBatteryModeChanged,
  });

  final _OnboardingPageData data;
  final bool showSetup;
  final String unit;
  final String batteryMode;
  final ValueChanged<String> onUnitChanged;
  final ValueChanged<String> onBatteryModeChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppGlassCard(
        padding: const EdgeInsets.all(20),
        borderRadius: 30,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.blueButtonGradient,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.blue.withValues(alpha: 0.30),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: Icon(data.icon, color: AppColors.white, size: 34),
            ),
            const SizedBox(height: 22),
            Text(
              data.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.white70,
                fontSize: 14,
                height: 1.36,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showSetup) ...<Widget>[
              const SizedBox(height: 22),
              _SetupGroup(
                title: 'Speed unit',
                children: <Widget>[
                  AppFilterChip(
                    label: 'km/h',
                    selected: unit == 'kmh',
                    icon: CupertinoIcons.speedometer,
                    onTap: () => onUnitChanged('kmh'),
                  ),
                  AppFilterChip(
                    label: 'mph',
                    selected: unit == 'mph',
                    icon: CupertinoIcons.speedometer,
                    onTap: () => onUnitChanged('mph'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SetupGroup(
                title: 'Battery mode',
                children: <Widget>[
                  AppFilterChip(
                    label: 'Balanced',
                    selected: batteryMode == 'balanced',
                    icon: CupertinoIcons.battery_75_percent,
                    onTap: () => onBatteryModeChanged('balanced'),
                  ),
                  AppFilterChip(
                    label: 'Saver',
                    selected: batteryMode == 'saver',
                    icon: CupertinoIcons.battery_25,
                    onTap: () => onBatteryModeChanged('saver'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupGroup extends StatelessWidget {
  const _SetupGroup({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: children,
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
  });

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (int i) {
        final bool active = i == index;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.blueSoft : AppColors.white24,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}
