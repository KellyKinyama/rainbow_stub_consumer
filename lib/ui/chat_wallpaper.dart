import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Subtle, original doodle wallpaper for chat backgrounds. Drawn with a
/// [CustomPainter] (not an image asset) so it carries no third-party
/// licensing and tints itself to the current palette.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = phonePaletteOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.chatWallpaper),
      child: CustomPaint(
        painter: _DoodlePainter(
          tint: palette.textSecondary.withValues(alpha: 0.05),
        ),
        child: child,
      ),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter({required this.tint});

  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const cell = 68.0;
    var row = 0;
    for (double y = 0; y < size.height + cell; y += cell) {
      final rowOffset = row.isEven ? 0.0 : cell / 2;
      var col = 0;
      for (double x = -cell; x < size.width + cell; x += cell) {
        final cx = x + rowOffset;
        final cy = y;
        switch ((row + col) % 4) {
          case 0:
            canvas.drawCircle(Offset(cx, cy), 8, p);
          case 1:
            final r = Rect.fromCircle(center: Offset(cx, cy), radius: 9);
            canvas.drawRRect(
              RRect.fromRectAndRadius(r, const Radius.circular(4)),
              p,
            );
            canvas.drawLine(Offset(cx - 3, cy + 9), Offset(cx - 8, cy + 13), p);
          case 2:
            canvas.drawLine(Offset(cx - 7, cy), Offset(cx + 7, cy), p);
            canvas.drawLine(Offset(cx, cy - 7), Offset(cx, cy + 7), p);
          default:
            canvas.drawCircle(Offset(cx - 4, cy), 2.5, p);
            canvas.drawCircle(Offset(cx + 4, cy), 2.5, p);
        }
        col++;
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _DoodlePainter old) => old.tint != tint;
}
