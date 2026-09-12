import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Row tile that mirrors Browser-Phone's `.buddy` / `.contact` layout:
/// 36 px circular avatar, name (15 px, ellipsized), presence subtitle
/// (12 px, secondary color), optional right-hand timestamp (11 px) or
/// unread badge / trailing widget. Selected / unread rows grow a
/// 3 px accent left border like the `.buddySelected` variant.
class PhoneRowTile extends StatelessWidget {
  const PhoneRowTile({
    super.key,
    required this.avatar,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.unreadCount = 0,
    this.accentOverride,
  });

  final Widget avatar;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final int unreadCount;
  final Color? accentOverride;

  @override
  Widget build(BuildContext context) {
    final palette = phonePaletteOf(context);
    final showAccent = selected || unreadCount > 0;
    final accent = accentOverride ?? PhoneTokens.accent;
    return Material(
      color: selected ? palette.rowSelected : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.rowHover,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PhoneTokens.rowPadding,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: PhoneTokens.rowSelectedBorderWidth,
                color: showAccent ? accent : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: PhoneTokens.avatarSize,
                height: PhoneTokens.avatarSize,
                child: avatar,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: PhoneTokens.titleFontSize,
                        fontWeight: unreadCount > 0
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: PhoneTokens.subtitleFontSize,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TrailingCluster(
                trailingText: trailingText,
                trailing: trailing,
                unreadCount: unreadCount,
                textColor: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrailingCluster extends StatelessWidget {
  const _TrailingCluster({
    required this.trailingText,
    required this.trailing,
    required this.unreadCount,
    required this.textColor,
  });

  final String? trailingText;
  final Widget? trailing;
  final int unreadCount;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailingText != null && trailingText!.isNotEmpty)
          Text(
            trailingText!,
            style: TextStyle(
              color: textColor,
              fontSize: PhoneTokens.timeStampFontSize,
            ),
          ),
        if (unreadCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _UnreadPill(count: unreadCount),
          )
        else if (trailing != null)
          Padding(padding: const EdgeInsets.only(top: 2), child: trailing),
      ],
    );
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: PhoneTokens.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Circular avatar with an optional presence dot at the bottom-right,
/// matching Browser-Phone's small avatar treatment.
class PhoneAvatar extends StatelessWidget {
  const PhoneAvatar({
    super.key,
    required this.label,
    this.presenceColor,
    this.icon,
    this.background,
  });

  final String label;
  final Color? presenceColor;
  final IconData? icon;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final palette = phonePaletteOf(context);
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: PhoneTokens.avatarSize,
          height: PhoneTokens.avatarSize,
          decoration: BoxDecoration(
            color: background ?? palette.avatarBg,
            shape: BoxShape.circle,
            border: Border.all(color: PhoneTokens.lightAvatarBorder, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 4,
                offset: Offset(1, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, color: Colors.white, size: 24)
              : Text(
                  label.isEmpty ? '?' : label[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        if (presenceColor != null)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: presenceColor,
              shape: BoxShape.circle,
              border: Border.all(color: palette.panelBg, width: 1.5),
            ),
          ),
      ],
    );
  }
}
