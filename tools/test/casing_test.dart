import 'package:test/test.dart';
import 'package:tools/src/util/casing.dart';

void main() {
  group('Casing.parse', () {
    test('normalizes every input form to the same words', () {
      for (final input in const [
        'user profile',
        'user_profile',
        'user-profile',
        'userProfile',
        'UserProfile',
        '  user   profile  ',
      ]) {
        final c = Casing.parse(input);
        expect(c.snake, 'user_profile', reason: input);
        expect(c.pascal, 'UserProfile', reason: input);
        expect(c.camel, 'userProfile', reason: input);
        expect(c.words, ['user', 'profile'], reason: input);
      }
    });

    test('single word', () {
      final c = Casing.parse('profile');
      expect(c.snake, 'profile');
      expect(c.pascal, 'Profile');
      expect(c.camel, 'profile');
    });

    test('digits are kept but a name cannot start with one', () {
      expect(Casing.parse('oauth2').snake, 'oauth2');
      expect(() => Casing.parse('2fa'), throwsFormatException);
    });

    test('rejects injectable / empty names', () {
      for (final bad in const ['', '  ', 'a\$b', 'a.b', 'a/b', "a'b", 'a;b']) {
        expect(() => Casing.parse(bad), throwsFormatException, reason: bad);
      }
    });
  });
}
