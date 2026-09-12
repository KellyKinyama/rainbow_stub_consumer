import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Semantic role for an in-call control, driving its fill colour.
enum PhoneCallButtonVariant {
  /// Idle control on the dark call surface (mic, camera, speaker…).
  neutral,

  /// A toggle that is currently engaged and wants attention
  /// (muted, camera off, on hold, locked). Browser-Phone tints these.
  active,

  /// Prominent green "answer" affordance.
  answer,

  /// Prominent red "hang up / reject" affordance.
  hangup,
}

/// Circular in-call control button porting Browser-Phone's
/// `.dialButtons.inCallButtons` treatment: a 56 px round button with a
/// centred glyph and an optional 9 px caption beneath it. Green for
/// answer, red for hang up, accent for engaged toggles, translucent
/// white for idle controls on the black call surface.
class PhoneCallButton extends StatelessWidget {
  const PhoneCallButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.label,
    this.variant = PhoneCallButtonVariant.neutral,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final PhoneCallButtonVariant variant;
  final double size;

  Color get _fill => switch (variant) {
    PhoneCallButtonVariant.neutral => Colors.white24,
    PhoneCallButtonVariant.active => PhoneTokens.accent,
    PhoneCallButtonVariant.answer => PhoneTokens.callActive,
    PhoneCallButtonVariant.hangup => PhoneTokens.danger,
  };

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: _fill,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: size * 0.42),
        ),
      ),
    );
    if (label == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 6),
        Text(
          label!,
          style: const TextStyle(
            color: Colors.white70,
            fontFamily: PhoneTokens.fontFamily,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
