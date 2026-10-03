import 'package:flutter/material.dart';

import 'app.dart';
import 'app_language.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addObserver(appLanguage);
  runApp(const LyricsFloatApp());
}
