import 'package:flutter/material.dart';
import 'features/search/search_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpenLexApp());
}

class OpenLexApp extends StatelessWidget {
  const OpenLexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenLex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: const SearchScreen(),
    );
  }
}

