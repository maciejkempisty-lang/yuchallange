import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/sqlite_store.dart';
import 'data/store.dart';
import 'model.dart';
import 'palette.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // sqflite has no web backend; the web preview keeps state in memory only.
  final Store store = kIsWeb ? MemoryStore() : await SqliteStore.open();
  final state = AppState(store);
  await state.load();
  runApp(YuApp(state: state));
}

class YuApp extends StatelessWidget {
  const YuApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YuChallenge',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('pl')],
      locale: const Locale('pl'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Pal.accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Pal.sea,
      ),
      home: HomeScreen(state: state),
    );
  }
}
