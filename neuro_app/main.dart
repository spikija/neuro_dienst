import 'package:flutter/material.dart';

void main() {
  runApp(const NeuroDienstApp());
}

class NeuroDienstApp extends StatelessWidget {
  const NeuroDienstApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroDienst',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('NeuroDienst'),
        ),
        body: const Center(
          child: Text('NeuroDienst started'),
        ),
      ),
    );
  }
}