import '../../app_state.dart';
import '../../common/action.dart';

class SetPasswordAction extends Action {
  SetPasswordAction(this.value);

  final String? value;

  @override
  AppState reduce() => state.copyWith.registration(password: value);
}
