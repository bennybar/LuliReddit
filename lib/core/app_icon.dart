import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The home-screen icon's colour (Settings → App icon). Each non-default
/// option is an alternate icon in the iOS asset catalog (`AppIcon-<key>`).
enum AppIcon {
  violet('Violet'),
  ocean('Ocean'),
  forest('Forest'),
  sunset('Sunset'),
  midnight('Midnight'),

  /// The mark in colour on white, like Google's own app icons.
  white('White');

  const AppIcon(this.label);
  final String label;

  String get asset => 'assets/icon/$name.png';

  static AppIcon parse(String? key) =>
      values.firstWhere((i) => i.name == key, orElse: () => violet);

  static const _channel = MethodChannel('ilay/app_icon');

  /// Switches the home-screen icon (iOS shows its own confirmation).
  static Future<void> apply(AppIcon icon) => _channel.invokeMethod<void>(
      'set', icon == violet ? null : 'AppIcon-${icon.name}');
}

/// [icon] as a rounded square, for the picker and the login screen.
class AppIconPreview extends StatelessWidget {
  const AppIconPreview(this.icon, {super.key, this.size = 24});
  final AppIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(icon.asset, width: size, height: size),
      );
}
