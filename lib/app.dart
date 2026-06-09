import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/deep_links.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/settings_controller.dart';
import 'router.dart';

class LuliApp extends ConsumerStatefulWidget {
  const LuliApp({super.key});

  @override
  ConsumerState<LuliApp> createState() => _LuliAppState();
}

class _LuliAppState extends ConsumerState<LuliApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleLink(uri);
    });
  }

  void _handleLink(Uri uri) {
    final route = routeForRedditUrl(uri);
    if (route != null) ref.read(routerProvider).push(route);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final seed = Color(settings.seedColor);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = settings.useDynamicColor;
        return MaterialApp.router(
          title: 'Luli for Reddit',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(
            useDynamic ? lightDynamic?.harmonized() : null,
            seed: seed,
          ),
          darkTheme: AppTheme.dark(
            useDynamic ? darkDynamic?.harmonized() : null,
            seed: seed,
            amoled: settings.amoled,
          ),
          themeMode: settings.themeMode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('he'), // RTL
            Locale('ar'), // RTL
            Locale('es'),
            Locale('fr'),
            Locale('de'),
          ],
          routerConfig: router,
        );
      },
    );
  }
}
