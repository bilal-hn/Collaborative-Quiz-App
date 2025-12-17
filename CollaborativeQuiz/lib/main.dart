import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Ensure this is imported if you use DefaultFirebaseOptions

// 🔴 FIX: Use the full package path instead of a relative path
import 'package:quizapp/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure we use the generated options (fixes common web/linux errors)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quiz Rooms',
      theme: ThemeData(primarySwatch: Colors.red),
      // 🔴 If this still fails, remove 'const' temporarily
      home: const LoginScreen(),
    );
  }
}
