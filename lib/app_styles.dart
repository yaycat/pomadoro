import 'package:flutter/material.dart';

/// Цвета, вынесенные из экрана таймера.
class AppColors {
  AppColors._();

  static const start = Color(0xFF2ECC71); // зеленый
  static const startDisabled = Color(0xFF1B7A3A); // темно‑зеленый

  static const pause = Color(0xFFFFD54F); // желтый
  static const cont = Color(0xFF8BC34A); // светло‑зеленый

  static const reset = Color(0xFFB71C1C); // темно‑красный

  static const textPrimary = Colors.black;
  static const textSecondary = Colors.black54;
}

/// Текстовые стили, используемые на экране таймера.
class AppTextStyles {
  AppTextStyles._();

  static const double timerScale = 2.5; // легко менять высоту/кегль таймера

  static TextStyle timer(TextTheme textTheme) =>
      (textTheme.displayLarge ?? const TextStyle(fontSize: 57)).copyWith(
        fontWeight: FontWeight.bold,
        fontSize: (textTheme.displayLarge?.fontSize ?? 60) * timerScale,
        letterSpacing: 1.2,
        color: AppColors.textPrimary,
      );

  static TextStyle phase(TextTheme textTheme) =>
      textTheme.titleMedium?.copyWith(color: AppColors.textSecondary) ??
      const TextStyle(fontSize: 18, color: AppColors.textSecondary);

  static const label = TextStyle(
    fontSize: 16,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w500,
  );
}
