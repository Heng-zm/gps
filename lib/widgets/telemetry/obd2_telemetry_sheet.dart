import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/obd2_telemetry_service.dart';
import '../../theme/app_theme.dart';
import '../common/app_glass_card.dart';

class Obd2TelemetrySheet extends StatefulWidget {
  const Obd2TelemetrySheet({super.key});

  @override
  State<Obd2TelemetrySheet> createState() => _Obd2TelemetrySheetState();
}

class _Obd2TelemetrySheetState extends State<Obd2TelemetrySheet> {
  final Obd2TelemetryService _service = Obd2TelemetryService.instance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Obd2ConnectionState>(
      valueListenable: _service.stateN,
      builder: (BuildContext context, Obd2ConnectionState state, _) {
        return ValueListenableBuilder<Obd2TelemetrySnapshot>(
          valueListenable: _service.snapshotN,
          builder: (BuildContext context, Obd2TelemetrySnapshot snap, _) {
            final bool isConnected = state == Obd2ConnectionState.connected ||
                state == Obd2ConnectionState.simulating;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Connection Header & Mode Toggle
                  _buildConnectionBar(state),
                  const SizedBox(height: 16),

                  // Big RPM & Gear Cockpit Gauge
                  _buildTachometerCard(snap, isConnected),
                  const SizedBox(height: 14),

                  // Engine Metrics Grid
                  _buildMetricsGrid(snap, isConnected),
                  const SizedBox(height: 16),

                  // Diagnostic DTC Codes
                  _buildDtcScannerCard(snap),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildConnectionBar(Obd2ConnectionState state) {
    final bool isSim = state == Obd2ConnectionState.simulating;
    final bool isConn = state == Obd2ConnectionState.connected;
    final bool isBusy = state == Obd2ConnectionState.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSim
                    ? AppColors.blueSoft.withValues(alpha: 0.15)
                    : isConn
                        ? AppColors.green.withValues(alpha: 0.15)
                        : isBusy
                            ? Colors.amber.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSim
                      ? AppColors.blueSoft.withValues(alpha: 0.3)
                      : isConn
                          ? AppColors.green.withValues(alpha: 0.4)
                          : isBusy
                              ? Colors.amber.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    CupertinoIcons.circle_filled,
                    size: 8,
                    color: isSim
                        ? AppColors.blueSoft
                        : isConn
                            ? AppColors.green
                            : isBusy
                                ? Colors.amber
                                : Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isSim
                        ? 'SIMULATION'
                        : isConn
                            ? 'CONNECTED (ELM327)'
                            : isBusy
                                ? 'CONNECTING...'
                                : 'DISCONNECTED',
                    style: TextStyle(
                      color: isSim
                          ? AppColors.blueSoft
                          : isConn
                              ? AppColors.green
                              : isBusy
                                  ? Colors.amber
                                  : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Real Connect / Disconnect button
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: isConn
                  ? Colors.red.withValues(alpha: 0.2)
                  : AppColors.green.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              minSize: 32,
              onPressed: () {
                HapticFeedback.lightImpact();
                if (isConn) {
                  _service.stop();
                } else {
                  _service.connectReal();
                }
              },
              child: Text(
                isConn ? 'Disconnect' : 'Connect Real ELM327',
                style: TextStyle(
                  color: isConn ? Colors.redAccent : AppColors.green,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Demo Sim Button
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: isSim
                  ? Colors.orange.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              minSize: 32,
              onPressed: () {
                HapticFeedback.lightImpact();
                if (isSim) {
                  _service.stop();
                } else {
                  _service.startSimulation();
                }
              },
              child: Text(
                isSim ? 'Stop Sim' : 'Demo Sim',
                style: TextStyle(
                  color: isSim ? Colors.orange : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<String>(
          valueListenable: _service.statusMessageN,
          builder: (_, String msg, __) {
            return Text(
              msg,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10.5,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTachometerCard(Obd2TelemetrySnapshot snap, bool isConnected) {
    final double rpmFrac = (snap.rpm / 8000.0).clamp(0.0, 1.0);
    final bool isRedline = snap.rpm >= 6200;

    return AppGlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 22,
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'ENGINE TACHOMETER',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        snap.rpm.toString(),
                        style: TextStyle(
                          color: isRedline ? AppColors.red : Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'RPM',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Current Gear Indicator
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isRedline
                        ? AppColors.red.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Center(
                  child: Text(
                    snap.gear > 0 ? snap.gear.toString() : 'N',
                    style: TextStyle(
                      color: isRedline ? AppColors.red : Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Linear RPM bar with redline segment
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: <Widget>[
                  FractionallySizedBox(
                    widthFactor: rpmFrac,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isRedline
                              ? <Color>[Colors.orange, AppColors.red]
                              : <Color>[AppColors.blueSoft, AppColors.blue],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(Obd2TelemetrySnapshot snap, bool isConnected) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: <Widget>[
        _GaugeTile(
          title: 'TURBO BOOST',
          value: '${snap.turboBoostBar.toStringAsFixed(2)} BAR',
          icon: CupertinoIcons.flame_fill,
          color: Colors.amberAccent,
        ),
        _GaugeTile(
          title: 'COOLANT TEMP',
          value: '${snap.coolantTempC}°C',
          icon: CupertinoIcons.thermometer,
          color: snap.coolantTempC > 105 ? AppColors.red : AppColors.blueSoft,
        ),
        _GaugeTile(
          title: 'ENGINE LOAD',
          value: '${snap.engineLoadPercent.round()}%',
          icon: CupertinoIcons.gauge,
          color: AppColors.green,
        ),
        _GaugeTile(
          title: 'FUEL FLOW',
          value: '${snap.fuelEconomyL100km.toStringAsFixed(1)} L/100km',
          icon: CupertinoIcons.drop_fill,
          color: Colors.purpleAccent,
        ),
      ],
    );
  }

  Widget _buildDtcScannerCard(Obd2TelemetrySnapshot snap) {
    final bool hasFaults = snap.faults.isNotEmpty;

    return AppGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                hasFaults
                    ? CupertinoIcons.exclamationmark_triangle_fill
                    : CupertinoIcons.checkmark_seal_fill,
                size: 18,
                color: hasFaults ? Colors.amberAccent : AppColors.green,
              ),
              const SizedBox(width: 8),
              Text(
                'ECU DIAGNOSTIC CODES (DTC)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (hasFaults)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 26,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _service.clearDtcCodes();
                  },
                  child: const Text(
                    'Clear Codes',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasFaults)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No active engine diagnostic trouble codes detected. All vehicle subsystems healthy.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            )
          else
            ...snap.faults.map((Obd2DtcFault fault) {
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          fault.code,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            fault.severity,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fault.descriptionEn,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fault.descriptionKm,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _GaugeTile extends StatelessWidget {
  const _GaugeTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              Icon(icon, size: 14, color: color),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
