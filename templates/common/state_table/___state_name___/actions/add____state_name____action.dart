import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../___state_name____selectors.dart';

class Add___StateName___Action extends ReduxAction<AppState> {
  Add___StateName___Action({required this.___stateName___});

  final IList<Object> ___stateName___;

  @override
  AppState reduce() {
    final byId = IMap<int, Object>.fromValues(
      values: ___stateName___,
      keyMapper: (v) => v.id,
    );

    final table = select___StateName___Table(state);
    final updatedTable = table.addAll(byId);

    return state.copyWith.___stateName___(table: updatedTable);
  }
}
