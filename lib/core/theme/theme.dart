import 'package:flutter/material.dart';
import 'colors.dart';
import 'typography.dart';
import 'spacing.dart';

/// Thème Material 3 unifié WhiteSilence.
/// Le but : que tous les modules héritent du même look sans effort.
class WSTheme {
  WSTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.light(
      primary: WSColors.glacierBlue,
      onPrimary: WSColors.snowWhite,
      secondary: WSColors.stoneGray,
      onSecondary: WSColors.snowWhite,
      surface: WSColors.snowWhite,
      onSurface: WSColors.slateDark,
      error: WSColors.avalancheRed,
      onError: WSColors.snowWhite,
      outline: WSColors.glacierMid,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: WSColors.snowWhite,

      textTheme: const TextTheme(
        displayLarge: WSText.display,
        titleLarge: WSText.title,
        titleMedium: WSText.heading,
        bodyLarge: WSText.body,
        bodyMedium: WSText.body,
        bodySmall: WSText.caption,
        labelSmall: WSText.micro,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: WSColors.snowWhite,
        foregroundColor: WSColors.slateDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: WSText.heading,
        // Icônes AppBar (retour, refresh dans la WebView, etc.) plus grosses
        // pour faciliter le tap au gant.
        iconTheme: IconThemeData(
          color: WSColors.slateDark,
          size: WSTouch.iconSize + 2,
        ),
        actionsIconTheme: IconThemeData(
          color: WSColors.slateDark,
          size: WSTouch.iconSize + 2,
        ),
        toolbarHeight: 60,
      ),

      cardTheme: CardThemeData(
        color: WSColors.snowWhite,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WSRadius.lg),
          side: const BorderSide(color: WSColors.glacierMid, width: 0.5),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: WSColors.glacierBlue,
          foregroundColor: WSColors.snowWhite,
          padding: const EdgeInsets.symmetric(
            horizontal: WSSpacing.lg,
            vertical: WSSpacing.md,
          ),
          // Hauteur minimale gants : pas de bouton qui passe sous 56dp.
          // largeur infinie permet aux Expanded de prendre toute la place.
          minimumSize: const Size(0, WSTouch.primaryHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WSRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: WSColors.slateDark,
          side: const BorderSide(color: WSColors.glacierMid, width: 0.5),
          padding: const EdgeInsets.symmetric(
            horizontal: WSSpacing.lg,
            vertical: WSSpacing.md,
          ),
          minimumSize: const Size(0, WSTouch.primaryHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WSRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: WSColors.glacierBlue,
          minimumSize: const Size(WSTouch.minTarget, WSTouch.minTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: WSSpacing.md,
            vertical: WSSpacing.sm,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          // IconButton standardisé à 56dp — beaucoup plus gros que les 40dp
          // par défaut de Material. Une zone de tap confortable au gant.
          minimumSize: const Size(WSTouch.iconButton, WSTouch.iconButton),
          padding: const EdgeInsets.all(WSSpacing.md),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(WSRadius.md)),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return WSColors.snowWhite;
          return WSColors.snowWhite;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return WSColors.glacierBlue;
          return WSColors.stoneGray.withOpacity(0.4);
        }),
        // Switch à 2× la taille standard pour cible tactile correcte
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: WSColors.snowWhite,
        selectedItemColor: WSColors.glacierBlue,
        unselectedItemColor: WSColors.stoneGray,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        // Icônes plus grosses pour les gants — passe par IconThemeData
        // (BottomNavigationBarThemeData n'a pas de iconSize direct).
        selectedIconTheme: IconThemeData(
          size: WSTouch.bottomBarIcon,
          color: WSColors.glacierBlue,
        ),
        unselectedIconTheme: IconThemeData(
          size: WSTouch.bottomBarIcon,
          color: WSColors.stoneGray,
        ),
        selectedLabelStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: WSColors.snowWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(WSRadius.xl),
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: WSColors.glacierMid,
        thickness: 0.5,
        space: 0.5,
      ),

      iconTheme: const IconThemeData(
        color: WSColors.slateDark,
        size: WSTouch.iconSize,
      ),
    );
  }
}
