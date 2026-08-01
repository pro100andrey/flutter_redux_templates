import '../../app_state.dart';
import '../../common/action.dart';

class SetConnectivityStatusAction extends Action {
  SetConnectivityStatusAction({required this.value});

  final bool value;

  @override
  AppState reduce() => state.copyWith.connectivity(isAvailable: value);
}
