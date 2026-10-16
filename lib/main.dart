import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/format.dart';
import 'services/notifier.dart';
import 'ui/home_shell.dart';
import 'ui/lms_web_page.dart';
import 'ui/nav.dart';
import 'ui/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await WebEnv.init();
  try {
    await Notifier.init();
  } catch (_) {}
  final app = await AppState.create();
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
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: app.themeMode,
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
