// ignore_for_file: non_constant_identifier_names

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/pdf_reader_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must add this line.
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    minimumSize: Size(600, 400),
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(ProviderScope(child: PdfReaderApp()));
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final virtualWindowFrameBuilder = VirtualWindowFrameInit();
    return MaterialApp(
      title: 'PDF Studio Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C6BC0)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
        ),
        iconTheme: const IconThemeData(size: 20, color: Colors.black54),
        textTheme: GoogleFonts.notoSansScTextTheme(),
      ),
      builder: (context, child) => virtualWindowFrameBuilder(context, child),
      home: const PdfReaderPage(),
    );
  }
}
