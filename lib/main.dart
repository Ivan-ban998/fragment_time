import 'package:flutter/material.dart';
import 'screens/home_stub.dart';

void main() {
  runApp(const FragmentTimeApp());
}

class FragmentTimeApp extends StatelessWidget {
  const FragmentTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FragmentTime - 碎片时间',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeStub(),
    );
  }
}
