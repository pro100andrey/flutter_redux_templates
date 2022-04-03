import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/pages/forgot_password_page.dart';
import 'package:ui/pages/log_in_page.dart';
import 'package:ui/pages/registration_page.dart';

import 'inputs.dart';
import 'knobs.dart';

List<Story> get pages => [
      Story(
        name: 'Pages/LogIn',
        builder: (context) => LogInPage(
          vm: LogInPageVm(
            isWaiting: context.knobIsWaiting(),
            email: context.newEmailInputVm(),
            password: context.newPasswordInputVm(),
            onPressedLogIn: context.knobOnPressed(label: 'Login Button'),
            onPressedForgotPassword:
                context.knobOnPressed(label: 'ForgotPassword Button'),
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
            onPressedRegister: context.knobOnPressed(label: 'Register Button'),
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
