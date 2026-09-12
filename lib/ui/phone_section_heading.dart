import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Section heading mirroring Browser-Phone's `.UiTextHeading`:
/// 17 px title, thin bottom border, optional chevron-down glyph on
/// the right hinting a collapsible group.
class PhoneSectionHeading extends StatelessWidget {
  const PhoneSectionHeading({
    super.key,
    required this.text,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 4),
  });

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = phonePaletteOf(context);
    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: PhoneTokens.fontFamily,
                  fontSize: PhoneTokens.sectionHeadingFontSize,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
