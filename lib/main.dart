import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';

import 'views/main_canvas_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive の初期化。
  // - Web では IndexedDB を使うためパスは不要。
  // - それ以外（Windows / Android 等）はアプリケーションサポートディレクトリを
  //   ホームディレクトリとして指定する。
  if (!kIsWeb) {
    final dir = await getApplicationSupportDirectory();
    Hive.init(dir.path);
  }

  runApp(
    const ProviderScope(
      child: Memoma3App(),
    ),
  );
}

/// メインアプリケーションルート。
///
/// [MaterialApp] と [Riverpod] の [ProviderScope] を設定する。
class Memoma3App extends StatelessWidget {
  const Memoma3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'memoma3',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueGrey,
        brightness: Brightness.dark,
      ),
      home: const MainCanvasScreen(),
    );
  }
}