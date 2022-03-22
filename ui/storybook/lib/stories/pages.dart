import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/pages/forgot_password_page.dart';
import 'package:ui/pages/log_in_page.dart';
import 'package:ui/pages/registration_page.dart';

import 'inputs_vm_knobs.dart';
import 'knobs.dart';

List<Story> get pages => [
      Story(
        name: 'Pages/LogIn',
        builder: (context) => LogInPage(
          vm: LogInPageVm(
            isWaiting: context.knobIsWaiting(),
            email: context.newEmailInputVm(),
            password: context.newPasswordInputVm(),
          ),
        ),
      ),
      Story(
        name: 'Pages/Registration',
        builder: (context) => RegistrationPage(
          vm: RegistrationPageVm(
            isWaiting: context.knobIsWaiting(),
            email: context.newEmailInputVm(),
            password: context.newPasswordInputVm(),
            confirmPassword: context.newPasswordInputVm(),
          ),
        ),
      ),
      Story(
        name: 'Pages/ForgotPassword',
        builder: (context) => ForgotPasswordPage(
          vm: ForgotPasswordPageVm(
            isWaiting: context.knobIsWaiting(),
          ),
        ),
      ),
    ];
