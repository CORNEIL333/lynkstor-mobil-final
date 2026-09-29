import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';

const _prefsKey = 'app_language';

/// Locale réactive (FR/EN) — persiste et force le rebuild de MaterialApp.
class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._prefs) : super(_read(_prefs)) {
    S.currentLanguage = state.languageCode;
  }

  final SharedPreferences _prefs;

  static Locale _read(SharedPreferences prefs) {
    final code = prefs.getString(_prefsKey) ?? 'fr';
    return Locale(code == 'en' ? 'en' : 'fr');
  }

  Future<void> setLanguage(String code) async {
    final normalized = code == 'en' ? 'en' : 'fr';
    await _prefs.setString(_prefsKey, normalized);
    S.currentLanguage = normalized;
    state = Locale(normalized);
  }

  bool get isEnglish => state.languageCode == 'en';
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return LocaleController(prefs);
    });
