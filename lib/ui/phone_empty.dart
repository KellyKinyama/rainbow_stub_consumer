import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Dashed-border empty-state card, mirroring Browser-Phone's `.NoItems`:
/// centred, 200 px wide, 2 px dashed accent border, 15 px radius, and
/// a soft `#9cb5d7`-style color for the label.
class PhoneNoItems extends StatelessWidget {
  const PhoneNoItems({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    const emptyBlue = Color(0xFF9CB5D7);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DottedBorder(
          child: SizedBox(
            width: 220,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) Icon(icon, size: 32, color: emptyBlue),
                  if (icon != null) const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: emptyBlue,
                      fontFamily: PhoneTokens.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple painted dashed-border container. Flutter has no built-in
/// dashed border in stable, so keep the painter local rather than
/// pulling a package for one screen decoration.
class DottedBorder extends StatelessWidget {
  const DottedBorder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DashedRectPainter(), child: child);
  }
}

class _DashedRectPainter extends CustomPainter {
  static const _radius = 15.0;
  static const _dash = 6.0;
  static const _gap = 4.0;
  static const _stroke = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    const emptyBlue = Color(0xFF9CB5D7);
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = emptyBlue
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke;

    // Walk each contour and paint dash/gap segments along it.
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) => false;
}
