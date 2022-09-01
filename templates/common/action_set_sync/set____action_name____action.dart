import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class Set___ActionName___Action extends ReduxAction<AppState> {
  Set___ActionName___Action({
    required this.___actionName___,
  });

  final String ___actionName___;

  @override
  AppState reduce() =>
      state.copyWith.___stateName___(___actionName___: ___actionName___);
}
