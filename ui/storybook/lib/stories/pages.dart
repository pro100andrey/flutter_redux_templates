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
          email: context.newEmailInputVm(),
          password: context.newPasswordInputVm(),
          onPressedLogIn: context.knobOnPressedOptional(label: 'Login Button'),
          onPressedForgotPassword:
              context.knobOnPressed(label: 'ForgotPassword Button'),
          onPressedRegister: context.knobOnPressed(label: 'Register Button'),
        ),
      ),
      Story(
        name: 'Pages/Registration',
        builder: (context) => RegistrationPage(
          isWaiting: context.knobIsWaiting(),
          email: context.newEmailInputVm(),
          password: context.newPasswordInputVm(),
          confirmPassword: context.newPasswordInputVm(),
          onPressedRegister:
              context.knobOnPressedOptional(label: 'Register Button'),
          onPressedBackToLogin: context.knobOnPressed(label: 'Back to Login'),
        ),
      ),
      Story(
        name: 'Pages/ForgotPassword',
        builder: (context) => ForgotPasswordPage(
          isWaiting: context.knobIsWaiting(),
          email: context.newEmailInputVm(),
          onPressedResetPassword:
              context.knobOnPressedOptional(label: 'Register Button'),
          onPressedBackToLogin: context.knobOnPressed(label: 'Back to Login'),
        ),
      ),
    ];
