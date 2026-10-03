import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';

enum AppLanguage { system, zhTW, en }

class LanguageController extends ValueNotifier<AppLanguage>
    with WidgetsBindingObserver {
  LanguageController() : super(AppLanguage.system);

  Locale get locale =>
      resolveLanguage(value, PlatformDispatcher.instance.locale);

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (value == AppLanguage.system) notifyListeners();
  }
}

Locale resolveLanguage(AppLanguage language, Locale systemLocale) {
  if (language == AppLanguage.zhTW ||
      (language == AppLanguage.system && systemLocale.languageCode == 'zh')) {
    return const Locale('zh', 'TW');
  }
  return const Locale('en');
}

final appLanguage = LanguageController();
String tr(String chinese, String english) =>
    appLanguage.locale.languageCode == 'zh' ? chinese : english;

String languageLabel(AppLanguage language) => switch (language) {
  AppLanguage.system => tr('跟隨系統', 'Follow system'),
  AppLanguage.zhTW => '繁體中文',
  AppLanguage.en => 'English',
};

String sourceLabel(String label) => switch (label) {
  '已連結 Google 帳號' => tr('已連結 Google 帳號', 'Google account connected'),
  'Spotify／桌面音樂軟體' => tr('Spotify／桌面音樂軟體', 'Spotify / desktop music apps'),
  'YouTube／瀏覽器媒體' => tr('YouTube／瀏覽器媒體', 'YouTube / browser media'),
  '所有支援的音樂與瀏覽器' => tr('所有支援的音樂與瀏覽器', 'All supported music apps and browsers'),
  '網易雲音樂' => tr('網易雲音樂', 'NetEase Music'),
  '酷狗音樂' => tr('酷狗音樂', 'Kugou Music'),
  '騰訊雲音速達' => tr('騰訊雲音速達', 'Tencent Cloud Music'),
  '尚未連結' => tr('尚未連結', 'Not connected'),
  _ => label,
};
