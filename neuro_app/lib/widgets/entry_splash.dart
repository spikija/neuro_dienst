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
  static const _splashImagePath = 'lib/screens/splasch_screen_1.png';

  late final AnimationController _controller;
  late final Animation<double> _curve;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.repeat(reverse: true);
    _finishTimer = Timer(const Duration(milliseconds: 2400), () {
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
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) {
          final pulse = _curve.value;

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF071826),
                      const Color(0xFF0A3A4A),
                      Color.lerp(
                        const Color(0xFF126C7A),
                        const Color(0xFFB71C1C),
                        0.18 + (pulse * 0.08),
                      )!,
                    ],
                  ),
                ),
              ),
              CustomPaint(painter: _NeuroStrokePainter(progress: pulse)),
              Center(
                child: Transform.scale(
                  scale: 0.96 + (pulse * 0.04),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFE53935,
                              ).withAlpha(26 + (pulse * 34).round()),
                              blurRadius: 36 + (pulse * 16),
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: Colors.white.withAlpha(
                                18 + (pulse * 28).round(),
                              ),
                              blurRadius: 26,
                              spreadRadius: -6,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: SizedBox(
                            width: 184,
                            height: 184,
                            child: Image.asset(
                              _splashImagePath,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'NeuroDienst',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Stroke team roster ready',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withAlpha(210),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: bottomPadding + 20,
                child: Text(
                  'v 0.2, Designed by Slaven Pikija, Created by Codex',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withAlpha(170),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NeuroStrokePainter extends CustomPainter {
  final double progress;

  const _NeuroStrokePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final vesselPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..color = Colors.white.withAlpha(44);
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.4
      ..color = const Color(
        0xFFFF5252,
      ).withAlpha(105 + (progress * 70).round());
    final nodePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withAlpha(58);

    final paths = <Path>[
      Path()
        ..moveTo(size.width * 0.08, size.height * 0.28)
        ..cubicTo(
          size.width * 0.25,
          size.height * 0.16,
          size.width * 0.40,
          size.height * 0.34,
          size.width * 0.56,
          size.height * 0.23,
        )
        ..cubicTo(
          size.width * 0.73,
          size.height * 0.12,
          size.width * 0.84,
          size.height * 0.22,
          size.width * 0.96,
          size.height * 0.16,
        ),
      Path()
        ..moveTo(size.width * 0.12, size.height * 0.74)
        ..cubicTo(
          size.width * 0.28,
          size.height * 0.58,
          size.width * 0.46,
          size.height * 0.82,
          size.width * 0.62,
          size.height * 0.62,
        )
        ..cubicTo(
          size.width * 0.76,
          size.height * 0.45,
          size.width * 0.86,
          size.height * 0.66,
          size.width * 0.96,
          size.height * 0.54,
        ),
      Path()
        ..moveTo(size.width * 0.43, size.height * 0.08)
        ..cubicTo(
          size.width * 0.35,
          size.height * 0.28,
          size.width * 0.55,
          size.height * 0.40,
          size.width * 0.47,
          size.height * 0.58,
        )
        ..cubicTo(
          size.width * 0.40,
          size.height * 0.73,
          size.width * 0.55,
          size.height * 0.83,
          size.width * 0.50,
          size.height,
        ),
    ];

    for (final path in paths) {
      canvas.drawPath(path, vesselPaint);
      _drawNodes(canvas, path, nodePaint);
    }

    final pulseIndex = (progress * paths.length).floor().clamp(
      0,
      paths.length - 1,
    );
    final metric = paths[pulseIndex].computeMetrics().first;
    final start = metric.length * (0.05 + (progress * 0.58));
    final end = math.min(metric.length, start + metric.length * 0.26);
    canvas.drawPath(metric.extractPath(start, end), pulsePaint);
  }

  void _drawNodes(Canvas canvas, Path path, Paint paint) {
    final metric = path.computeMetrics().first;

    for (final fraction in const [0.12, 0.36, 0.62, 0.86]) {
      final tangent = metric.getTangentForOffset(metric.length * fraction);

      if (tangent != null) {
        canvas.drawCircle(tangent.position, 3.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NeuroStrokePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
