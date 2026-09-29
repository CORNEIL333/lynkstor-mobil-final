import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';

const _nameKey = 'lynk_name';
const _accentKey = 'lynk_accent';

class LynkPrefs {
  const LynkPrefs({this.name = 'Lynk', this.accent = 'coral'});

  final String name;
  final String accent;

  Color get accentColor => switch (accent) {
    'sky' => AppColors.sky,
    'ocean' => AppColors.ocean,
    _ => AppColors.coral,
  };

  LynkPrefs copyWith({String? name, String? accent}) =>
      LynkPrefs(name: name ?? this.name, accent: accent ?? this.accent);
}

class LynkPrefsController extends StateNotifier<LynkPrefs> {
  LynkPrefsController(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static LynkPrefs _read(SharedPreferences prefs) => LynkPrefs(
    name: prefs.getString(_nameKey) ?? 'Lynk',
    accent: prefs.getString(_accentKey) ?? 'coral',
  );

  Future<void> setName(String name) async {
    final trimmed = name.trim().isEmpty ? 'Lynk' : name.trim();
    await _prefs.setString(_nameKey, trimmed);
    state = state.copyWith(name: trimmed);
  }

  Future<void> setAccent(String accent) async {
    await _prefs.setString(_accentKey, accent);
    state = state.copyWith(accent: accent);
  }
}

final lynkPrefsProvider = StateNotifierProvider<LynkPrefsController, LynkPrefs>(
  (ref) {
    return LynkPrefsController(ref.watch(sharedPreferencesProvider));
  },
);
