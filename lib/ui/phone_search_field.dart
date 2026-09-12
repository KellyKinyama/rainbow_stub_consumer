import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Pill-shaped search input mirroring Browser-Phone's `.searchClean`:
/// filled with the row-hover tone (light-grey `#EAEAEA` in the CSS),
/// no border, prefix search icon in the secondary text color, 999-px
/// radius. Debouncing is left to the caller.
class PhoneSearchField extends StatelessWidget {
  const PhoneSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 4),
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = phonePaletteOf(context);
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: TextStyle(
          fontFamily: PhoneTokens.fontFamily,
          fontSize: 14,
          color: palette.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: palette.textSecondary),
          prefixIcon: Icon(Icons.search, color: palette.textSecondary),
          filled: true,
          fillColor: palette.rowHover,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
