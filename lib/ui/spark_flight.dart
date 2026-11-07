import 'package:flutter/material.dart';

import '../palette.dart';

class Flight {
  Flight({
    required this.id,
    required this.from,
    required this.to,
    required this.delay,
    required this.counts,
    required this.bend,
  });

  final int id;
  final Offset from, to;
  final Duration delay;

  /// Whether arriving adds one to the visible balance.
  final bool counts;

  /// -1..1, how far the arc swings sideways.
  final double bend;
}

/// One spark flying along a curved path from a goal button to the counter.
class SparkFlight extends StatefulWidget {
  const SparkFlight({super.key, required this.flight, required this.onArrive});

  final Flight flight;
  final VoidCallback onArrive;

  @override
  State<SparkFlight> createState() => _SparkFlightState();
}

class _SparkFlightState extends State<SparkFlight>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onArrive();
    });
    Future.delayed(widget.flight.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.flight;
    final control = Offset(
      (f.from.dx + f.to.dx) / 2 - 90 + f.bend * 70,
      (f.from.dy + f.to.dy) / 2 + f.bend * 40,
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.value == 0) return const SizedBox.shrink();
        final t = Curves.easeInOutCubic.transform(_c.value);
        final u = 1 - t;
        final pos = f.from * (u * u) + control * (2 * u * t) + f.to * (t * t);
        final scale = t < 0.15 ? t / 0.15 * 1.3 : 1.3 - (t - 0.15) * 0.7;
        return Positioned(
          left: pos.dx - 11,
          top: pos.dy - 11,
          child: Transform.rotate(
            angle: t * 5,
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.auto_awesome,
                size: 22,
                color: Pal.spark,
                shadows: [Shadow(color: Pal.spark, blurRadius: 14)],
              ),
            ),
          ),
        );
      },
    );
  }
}
