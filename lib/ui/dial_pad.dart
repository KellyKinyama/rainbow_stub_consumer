import 'package:flutter/material.dart';

/// A 3×4 phone keypad. Emits the tapped key ('0'–'9', '*', '#') via
/// [onKey]; long-pressing '0' emits '+' (for E.164 dialing).
class DialPad extends StatelessWidget {
  const DialPad({super.key, required this.onKey, this.compact = false});

  final ValueChanged<String> onKey;
  final bool compact;

  static const _rows = <List<(String, String)>>[
    [('1', ''), ('2', 'ABC'), ('3', 'DEF')],
    [('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO')],
    [('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ')],
    [('*', ''), ('0', '+'), ('#', '')],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (digit, sub) in row)
                  _Key(
                    digit: digit,
                    sub: sub,
                    compact: compact,
                    onTap: () => onKey(digit),
                    onLongPress: digit == '0' ? () => onKey('+') : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.digit,
    required this.sub,
    required this.onTap,
    required this.compact,
    this.onLongPress,
  });

  final String digit;
  final String sub;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 56.0 : 72.0;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                digit,
                style: TextStyle(
                  fontSize: compact ? 22 : 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
