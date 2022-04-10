import 'package:localization/localization.dart';
import 'package:validator/validator.dart';

final emailValidator = MultiValidator([
  RequiredValidator(error: S.current.fieldIsRequired),
  EmailValidator(error: S.current.invalidEmail),
]);

final passwordValidator = MultiValidator([
  RequiredValidator(error: 'Required field'),
  MinLengthValidator(8, error: 'Min length 8'),
  HasUppercaseValidator(error: 'Must contain at least one uppercase'),
  HasLowercaseValidator(error: 'Must contain at least one lowercase'),
]);
