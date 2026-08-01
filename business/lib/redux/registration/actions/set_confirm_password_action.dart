import '../../app_state.dart';
import '../../common/action.dart';

class SetConfirmPasswordAction extends Action {
  SetConfirmPasswordAction(this.value);

  final String? value;

  @override
  AppState reduce() => state.copyWith.registration(confirmPassword: value);
}
