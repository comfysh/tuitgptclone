import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/format.dart';
import 'services/desktop_tray.dart';
import 'services/notifier.dart';
import 'services/web_env.dart';
import 'ui/design.dart' show Brand;
import 'ui/home_shell.dart';
import 'ui/nav.dart';
import 'ui/welcome_screen.dart';

/// [args]: launch arguments; on Windows "--minimized" starts hidden in the tray.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await WebEnv.init();
  try {
    await Notifier.init();
  } catch (_) {}
  final app = await AppState.create();
  // Windows only (no-op elsewhere): tray icon, close-to-tray, hidden start.
  await DesktopTray.init(app, args: args);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => NavController()),
    ],
    child: const TuitMateApp(),
  ));
}

class TuitMateApp extends StatelessWidget {
  const TuitMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.language;
    return MaterialApp(
      title: 'TuitMate',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, style: app.style),
      darkTheme: buildTheme(Brightness.dark, style: app.style, pureBlack: app.settings.pureBlack),
      themeMode: app.themeMode,
      // The colours screens take from Brand follow the theme on screen.
      builder: (context, child) {
        final b = switch (app.themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };
        Brand.apply(app.style, b, pureBlack: app.settings.pureBlack);
        return child ?? const SizedBox.shrink();
      },
      locale: Locale(lang == 'uz' ? 'uz' : lang),
      supportedLocales: const [Locale('en'), Locale('ru'), Locale('uz')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: app.loggedIn ? const HomeShell() : const WelcomeScreen(),
    );
  }
}
