import 'package:flutter/material.dart';

/// Palette + spacing tokens ported from Browser-Phone
/// (C:\www\node\Browser-Phone\Phone\phone.css + phone.light.css +
/// phone.dark.css). Keep raw hex values here so widgets can pull the
/// exact tone the JS phone uses.
class PhoneTokens {
  const PhoneTokens._();

  // Accent — used for pinned badges, selected left border, primary
  // buttons, links.
  static const Color accent = Color(0xFF3478F3);

  // Positive / negative call states.
  static const Color callActive = Color(0xFF40BD3F);
  static const Color callHold = Color(0xFFCC9009);
  static const Color danger = Color(0xFFAC2121);

  // Light theme.
  static const Color lightBodyBg = Color(0xFFF6F6F6);
  static const Color lightPanelBg = Color(0xFFFFFFFF);
  static const Color lightChatWallpaper = Color(0xFFEFEADC);
  static const Color lightTheirBubble = Color(0xFFECF7E6);
  static const Color lightOurBubble = Color(0xFFF1F9FF);
  static const Color lightRowHover = Color(0xFFE1E1E1);
  static const Color lightRowSelected = Color(0xFFE1E1E1);
  static const Color lightDivider = Color(0xFFCCCCCC);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF999999);
  static const Color lightAvatarBg = Color(0xFFCCCCCC);
  static const Color lightAvatarBorder = Color(0xFFFFFFFF);

  // Dark theme.
  static const Color darkBodyBg = Color(0xFF1B1B1B);
  static const Color darkPanelBg = Color(0xFF222222);
  static const Color darkChatWallpaper = Color(0xFF292929);
  static const Color darkTheirBubble = Color(0xFF2C423A);
  static const Color darkOurBubble = Color(0xFF2B3842);
  static const Color darkRowHover = Color(0xFF333333);
  static const Color darkRowSelected = Color(0xFF404040);
  static const Color darkDivider = Color(0xFF3E3E3E);
  static const Color darkTextPrimary = Color(0xFFE1E1E1);
  static const Color darkTextSecondary = Color(0xFF999999);

  // Spacing / sizing.
  static const double rowHeight = 48;
  static const double avatarSize = 36;
  static const double avatarSmall = 18;
  static const double bubbleRadius = 10;
  static const double bubbleMaxWidthFactor = 0.85;
  static const double rowPadding = 8;
  static const double rowRadius = 5;
  static const double rowSelectedBorderWidth = 3;
  static const double timeStampFontSize = 11;
  static const double subtitleFontSize = 12;
  static const double titleFontSize = 15;
  static const double sectionHeadingFontSize = 17;
  static const String fontFamily = 'Roboto';
}

/// Convenience getter — returns the palette matching the current
/// [Brightness].
PhonePalette phonePaletteOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const PhonePalette.dark()
    : const PhonePalette.light();

class PhonePalette {
  const PhonePalette({
    required this.bodyBg,
    required this.panelBg,
    required this.chatWallpaper,
    required this.theirBubble,
    required this.ourBubble,
    required this.rowHover,
    required this.rowSelected,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.avatarBg,
  });

  const PhonePalette.light()
    : bodyBg = PhoneTokens.lightBodyBg,
      panelBg = PhoneTokens.lightPanelBg,
      chatWallpaper = PhoneTokens.lightChatWallpaper,
      theirBubble = PhoneTokens.lightTheirBubble,
      ourBubble = PhoneTokens.lightOurBubble,
      rowHover = PhoneTokens.lightRowHover,
      rowSelected = PhoneTokens.lightRowSelected,
      divider = PhoneTokens.lightDivider,
      textPrimary = PhoneTokens.lightTextPrimary,
      textSecondary = PhoneTokens.lightTextSecondary,
      avatarBg = PhoneTokens.lightAvatarBg;

  const PhonePalette.dark()
    : bodyBg = PhoneTokens.darkBodyBg,
      panelBg = PhoneTokens.darkPanelBg,
      chatWallpaper = PhoneTokens.darkChatWallpaper,
      theirBubble = PhoneTokens.darkTheirBubble,
      ourBubble = PhoneTokens.darkOurBubble,
      rowHover = PhoneTokens.darkRowHover,
      rowSelected = PhoneTokens.darkRowSelected,
      divider = PhoneTokens.darkDivider,
      textPrimary = PhoneTokens.darkTextPrimary,
      textSecondary = PhoneTokens.darkTextSecondary,
      avatarBg = PhoneTokens.lightAvatarBg;

  final Color bodyBg;
  final Color panelBg;
  final Color chatWallpaper;
  final Color theirBubble;
  final Color ourBubble;
  final Color rowHover;
  final Color rowSelected;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color avatarBg;
}
