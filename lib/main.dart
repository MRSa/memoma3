import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'views/main_canvas_screen.dart';

void main() {
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