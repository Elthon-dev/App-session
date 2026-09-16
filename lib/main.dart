import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'src/screens/home_screen.dart';
import 'src/theme.dart';

void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logError(details.exceptionAsString(), details.stack);
  };
  runZonedGuarded(() => runApp(const OpenBridgeApp()), (e, st) {
    _logError('$e', st);
  });
}

Future<void> _logError(String msg, StackTrace? st) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/crash.log');
    final ts = DateTime.now().toIso8601String();
    await f.writeAsString('[$ts] $msg\n${st ?? ''}\n\n', mode: FileMode.append);
  } catch (_) {}
}

class OpenBridgeApp extends StatelessWidget {
  const OpenBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenBridge',
      debugShowCheckedModeBanner: false,
      theme: buildNordTheme(),
      home: const HomeScreen(),
    );
  }
}