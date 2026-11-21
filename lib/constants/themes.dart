import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';

/// CodeNote's look, in one place.
///
/// The colors come from the logo: an electric blue to violet gradient with
/// magenta waves, around a `>_` terminal prompt. Code is always set in
/// JetBrains Mono, and small "terminal" touches (comment-style section
/// labels, a blinking cursor) give the app its personality.
class AppBrand {
  AppBrand._();

  static const violet = Color(0xFF7B5CFF);
  static const violetLight = Color(0xFFB3A2FF);
  static const blue = Color(0xFF3D7BFF);
  static const magenta = Color(0xFFD45CF0);
  static const mint = Color(0xFF3DDC97); // "it worked" green, like a passing test
  static const amber = Color(0xFFFFB347); // pins and reminders

  static const mono = 'JetBrainsMono';

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, violet, magenta],
  );

  /// One corner size for cards, one for small pieces. Used everywhere.
  static const radius = 20.0;
  static const radiusSmall = 12.0;
}

/// Extra theme values Material doesn't have a slot for.
@immutable
class CodeNoteTokens extends ThemeExtension<CodeNoteTokens> {
  const CodeNoteTokens({
    required this.codeBackground,
    required this.codeTheme,
    required this.pin,
    required this.success,
    required this.subtle,
  });

  /// Background behind code blocks.
  final Color codeBackground;

  /// Syntax colors for code blocks.
  final Map<String, TextStyle> codeTheme;

  /// Pins and reminders.
  final Color pin;

  /// Confirmations ("Copied", "Restored").
  final Color success;

  /// Quiet text: dates, hints, comment-style labels. Checked for contrast.
  final Color subtle;

  @override
  CodeNoteTokens copyWith({
    Color? codeBackground,
    Map<String, TextStyle>? codeTheme,
    Color? pin,
    Color? success,
    Color? subtle,
  }) {
    return CodeNoteTokens(
      codeBackground: codeBackground ?? this.codeBackground,
      codeTheme: codeTheme ?? this.codeTheme,
      pin: pin ?? this.pin,
      success: success ?? this.success,
      subtle: subtle ?? this.subtle,
    );
  }

  @override
  CodeNoteTokens lerp(ThemeExtension<CodeNoteTokens>? other, double t) {
    if (other is! CodeNoteTokens) return this;
    return CodeNoteTokens(
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      codeTheme: t < 0.5 ? codeTheme : other.codeTheme,
      pin: Color.lerp(pin, other.pin, t)!,
      success: Color.lerp(success, other.success, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
    );
  }
}

extension CodeNoteThemeX on BuildContext {
  CodeNoteTokens get tokens => Theme.of(this).extension<CodeNoteTokens>()!;
}

/// Monospace style for code and the small terminal touches.
TextStyle monoStyle(BuildContext context,
    {double size = 13, FontWeight weight = FontWeight.w400, Color? color}) {
  return TextStyle(
    fontFamily: AppBrand.mono,
    fontSize: size,
    fontWeight: weight,
    height: 1.5,
    color: color ?? Theme.of(context).colorScheme.onSurface,
  );
}

Map<String, TextStyle> _withoutBackground(Map<String, TextStyle> theme) {
  final copy = Map<String, TextStyle>.of(theme);
  final root = copy['root'];
  if (root != null) {
    copy['root'] = root.copyWith(backgroundColor: Colors.transparent);
  }
  return copy;
}

ThemeData _build(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppBrand.violet,
    brightness: brightness,
  ).copyWith(
    primary: isDark ? AppBrand.violetLight : AppBrand.violet,
    onPrimary: isDark ? const Color(0xFF1B1240) : Colors.white,
    secondary: AppBrand.blue,
    tertiary: AppBrand.magenta,
    // Three clear surface levels so cards, bars and the page don't blend.
    surface: isDark ? const Color(0xFF111225) : const Color(0xFFF8F7FF),
    surfaceContainerLow:
        isDark ? const Color(0xFF17182E) : const Color(0xFFF1EFFC),
    surfaceContainer: isDark ? const Color(0xFF1D1F38) : const Color(0xFFEAE7FA),
    surfaceContainerHigh:
        isDark ? const Color(0xFF25274A) : const Color(0xFFE1DDF6),
    surfaceContainerHighest:
        isDark ? const Color(0xFF2E3058) : const Color(0xFFD8D3F1),
    outlineVariant: isDark ? const Color(0xFF34365C) : const Color(0xFFD3CFEA),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
  );

  final text = base.textTheme.copyWith(
    headlineMedium: base.textTheme.headlineMedium
        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium:
        base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
    labelSmall: base.textTheme.labelSmall?.copyWith(letterSpacing: 0.2),
  );

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppBrand.radius),
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radius),
        side: BorderSide(color: scheme.outlineVariant.withAlpha(140)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      shape: rounded,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppBrand.radius)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF2E3058) : const Color(0xFF1D1F38),
      contentTextStyle: const TextStyle(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500, height: 1.35),
      actionTextColor: AppBrand.violetLight,
      elevation: 6,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      closeIconColor: Colors.white70,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        side: BorderSide(color: AppBrand.violet.withAlpha(isDark ? 90 : 60)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
      ),
      labelStyle: TextStyle(
        fontFamily: AppBrand.mono,
        fontSize: 12,
        color: scheme.onSurface,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radius),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withAlpha(40),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3C68) : const Color(0xFF1D1F38),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    extensions: [
      CodeNoteTokens(
        codeBackground:
            isDark ? const Color(0xFF0B0C1A) : const Color(0xFFFFFFFF),
        codeTheme: _withoutBackground(
            isDark ? atomOneDarkTheme : atomOneLightTheme),
        pin: AppBrand.amber,
        success: AppBrand.mint,
        subtle: isDark ? const Color(0xFFA3A5C8) : const Color(0xFF5F6283),
      ),
    ],
  );
}

final mainTheme = _build(Brightness.light);
final darkTheme = _build(Brightness.dark);
