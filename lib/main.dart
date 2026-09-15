import 'package:flutter/material.dart';
import 'src/screens/home_screen.dart';
import 'src/theme.dart';

void main() => runApp(const OpenBridgeApp());

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