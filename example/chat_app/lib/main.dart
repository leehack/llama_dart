import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'screens/app_shell_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLifecycleListener _listener;
  final ChatProvider _chatProvider = ChatProvider();

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onDetach: () {
        unawaited(_chatProvider.shutdown());
      },
      onExitRequested: () async {
        await _chatProvider.shutdown();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    unawaited(_chatProvider.shutdown());
    _chatProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _chatProvider,
      child: MaterialApp(
        title: 'llamadart chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1D273A),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          textTheme: GoogleFonts.manropeTextTheme(),
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5D89FF),
            brightness: Brightness.dark,
            surface: const Color(0xFF0B101A),
          ),
          useMaterial3: true,
          textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
          ),
        ),
        themeMode: ThemeMode.dark,
        home: const AppShellScreen(),
      ),
    );
  }
}
