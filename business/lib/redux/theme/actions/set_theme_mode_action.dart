// `material.dart` exports its own `Action` (the widgets/intents one), which
// collides with this app's action base — hide it.
import 'package:flutter/material.dart' show ThemeMode;

import '../../app_state.dart';
import '../../common/action.dart';

class SetThemeModeAction extends Action {
  SetThemeModeAction(this.mode);

  final ThemeMode mode;

  @override
  AppState reduce() => state.copyWith.theme(mode: mode);
}
