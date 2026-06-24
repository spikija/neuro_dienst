import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class EntrySplash extends StatefulWidget {
  final VoidCallback onFinished;

  const EntrySplash({super.key, required this.onFinished});

  @override
  State<EntrySplash> createState() => _EntrySplashState();
}

class _EntrySplashState extends State<EntrySplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
    _finishTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        widget.onFinished();
      }
    });
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) {
          final value = _curve.value;
          final pulse = math.sin(value * math.pi);

          return Center(
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.88 + (0.16 * value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withAlpha(
                              (48 + pulse * 72).round(),
                            ),
                            blurRadius: 22 + (pulse * 20),
                            spreadRadius: 2 + (pulse * 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.calendar_month,
                        size: 44,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'NeuroDienst',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dienstplan bereit',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
