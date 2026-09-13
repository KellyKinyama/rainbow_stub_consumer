import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Circular action button matching Browser-Phone `.roundButtons`:
/// 32 px diameter, 16 px icon, transparent background by default,
/// accent-blue icon color, subtle hover / pressed tint.
class PhoneRoundButton extends StatelessWidget {
  const PhoneRoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 40,
    this.iconSize = 24,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = phonePaletteOf(context);
    final resolvedColor = color ?? PhoneTokens.accent;
    final btn = Material(
      color: background ?? Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        hoverColor: palette.rowHover,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: resolvedColor),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
