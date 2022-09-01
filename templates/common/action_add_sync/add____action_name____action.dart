import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';

class Add___ActionName___Action extends ReduxAction<AppState> {
  Add___ActionName___Action({
    required this.___actionName___,
  });

  final IList<Object>? ___actionName___;

  @override
  AppState? reduce() {
    if (___actionName___ == null) {
      return null;
    }

    final byId = IMap<int, Object>.fromValues(
      values: ___actionName___!,
      keyMapper: (v) => v.id,
    );

    final table = state.___actionName___.table.addAll(byId);

    return state.copyWith.___actionName___(table: table);
  }
}
