import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'options.dart';

class FirebaseInit {
  static Future<FirebaseApp?> connect() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      return await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
        name: "reward_master",
      );
    } catch (e) {
      debugPrint("Error firebase init : $e");
      return null;
    }
  }
}
