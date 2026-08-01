import 'package:test/test.dart';
import 'package:tools/src/preview/vm_reader.dart';

/// Reading a render model out of source is what a generated preview is built
/// from: the fields decide the sample values and which variants are worth
/// showing, and `props` decides whether the model tells the truth in `==`.
void main() {
  ViewModel read(String source, String className) {
    final vm = VmReader.readClass(source, className);
    expect(vm, isNotNull, reason: 'expected to find $className');
    return vm!;
  }

  VmField field(ViewModel vm, String name) =>
      vm.fields.firstWhere((f) => f.name == name);

  const card = '''
final class ExerciseCardVm extends Equatable {
  const ExerciseCardVm({
    required this.id,
    required this.title,
    required this.muscles,
    this.badge,
    this.done = false,
  });

  final String id;
  final String title;
  final List<String> muscles;
  final String? badge;
  final bool done;

  static const placeholder = 1;

  @override
  List<Object?> get props => [id, title, muscles, badge, done];
}
''';

  test('fields come back in declaration order', () {
    expect(read(card, 'ExerciseCardVm').fields.map((f) => f.name), [
      'id',
      'title',
      'muscles',
      'badge',
      'done',
    ]);
  });

  test('the type is taken from the field, not the bare `this.x`', () {
    // The house style writes `this.title` with the type on the field below.
    // Reading only the parameter reports every model in the package as
    // `dynamic`, which makes the value table useless.
    final vm = read(card, 'ExerciseCardVm');
    expect(field(vm, 'title').type, 'String');
    expect(field(vm, 'muscles').type, 'List<String>');
  });

  test('required, optional and defaulted are told apart', () {
    final vm = read(card, 'ExerciseCardVm');
    expect(field(vm, 'title').required, isTrue);
    expect(field(vm, 'badge').required, isFalse);
    expect(field(vm, 'done').defaultValue, 'false');
    expect(field(vm, 'title').defaultValue, isNull);
  });

  test('nullability and element type are derived from the written type', () {
    final vm = read(card, 'ExerciseCardVm');
    expect(field(vm, 'badge').nullable, isTrue);
    expect(field(vm, 'badge').bareType, 'String');
    expect(field(vm, 'title').nullable, isFalse);
    expect(field(vm, 'muscles').elementType, 'String');
    expect(field(vm, 'title').elementType, isNull);
  });

  test('a static field is not a constructor parameter', () {
    expect(
      read(card, 'ExerciseCardVm').fields.map((f) => f.name),
      isNot(contains('placeholder')),
    );
  });

  test('props are read, and a model that lists them all is clean', () {
    final vm = read(card, 'ExerciseCardVm');
    expect(vm.equality, ['id', 'title', 'muscles', 'badge', 'done']);
    expect(vm.fieldsOutsideEquality, isEmpty);
  });

  test('a value field left out of equality is reported', () {
    // The case this exists for, in the form it takes in a clone: somebody adds
    // a field to a view-model six months later and does not add it to the
    // equality list. Two models with different values then compare equal, so
    // the connector's rebuild never reaches the widget.
    const leaky = '''
final class RowVm extends Equatable {
  const RowVm({required this.title, required this.badge});

  final String title;
  final String badge;

  @override
  List<Object?> get props => [title];
}
''';
    expect(read(leaky, 'RowVm').fieldsOutsideEquality.map((f) => f.name), [
      'badge',
    ]);
  });

  test('a callback left out of equality is not reported', () {
    // `fromStore()` builds a fresh closure every time, so a view-model that
    // compared them would be unequal to itself on every rebuild. Ten of this
    // repository's eleven fields outside equality are exactly this.
    const callbacks = '''
final class RowVm extends Equatable {
  const RowVm({required this.title, required this.onTap, this.onChanged});

  final String title;
  final VoidCallback onTap;
  final ValueChanged<String>? onChanged;

  @override
  List<Object?> get props => [title];
}
''';
    expect(read(callbacks, 'RowVm').fieldsOutsideEquality, isEmpty);
  });

  test(
    'equality is read from super(equals:), which is what this repo writes',
    () {
      // The reader looked only for `props`, which is equatable's shape. On all
      // eight of this repository's view-models it therefore read an empty list,
      // and its one check had never fired and could not have.
      const vm = '''
class _Vm extends Vm {
  _Vm({required this.email, required this.badge, required this.onTap})
      : super(equals: [email]);

  final String email;
  final String badge;
  final VoidCallback onTap;
}
''';
      final read_ = read(vm, '_Vm');
      expect(read_.equality, ['email']);
      expect(read_.fieldsOutsideEquality.map((f) => f.name), ['badge']);
    },
  );

  test('a class that writes its own == is not reported at all', () {
    // It has said what equality means. This repository has one — a dialog
    // view-model whose `==` is deliberately not an equivalence relation, with a
    // comment saying so — and a rule that reported it would be arguing with a
    // decision already taken.
    const own = '''
class _Vm extends Vm {
  _Vm({required this.rebuild, required this.title}) : super(equals: [title]);

  final bool rebuild;
  final String title;

  @override
  bool operator ==(Object other) => !rebuild;
}
''';
    final vm = read(own, '_Vm');
    expect(vm.declaresOwnEquals, isTrue);
    expect(vm.fieldsOutsideEquality, isEmpty);
  });

  test('a computed equals list is left unread rather than half-read', () {
    const computed = '''
class _Vm extends Vm {
  _Vm({required this.a, required this.b}) : super(equals: [a, ...more]);

  final String a;
  final String b;
}
''';
    final vm = read(computed, '_Vm');
    expect(vm.equality, isEmpty);
    expect(vm.fieldsOutsideEquality, isEmpty);
  });

  test('a computed props getter is left unread rather than half-read', () {
    const computed = '''
final class RowVm extends Equatable {
  const RowVm({required this.title});

  final String title;

  @override
  List<Object?> get props => [title, ...extra];
}
''';
    final vm = read(computed, 'RowVm');
    // `...extra` cannot be resolved without the element model, so claiming
    // "title is the whole of props" would produce false lint hits.
    expect(vm.equality, isEmpty);
    expect(vm.fieldsOutsideEquality, isEmpty);
  });

  test('a widget class is not mistaken for a model', () {
    // A widget's constructor is also all-`this.x`, which is why callers name
    // the class they want instead of taking the first that parses.
    const file = '''
final class CardVm extends Equatable {
  const CardVm({required this.title});
  final String title;
  @override
  List<Object?> get props => [title];
}

class Card extends StatelessWidget {
  const Card({required this.vm, super.key});
  final CardVm vm;
}
''';
    expect(VmReader.readClass(file, 'CardVm'), isNotNull);
    expect(VmReader.read(file).map((v) => v.className), contains('CardVm'));
  });

  test('a class with no generative constructor is skipped', () {
    const freezed = '''
abstract class LogInState with _\$LogInState {
  const factory LogInState({String? email}) = _LogInState;
}
''';
    expect(VmReader.readClass(freezed, 'LogInState'), isNull);
  });

  test('an absent class reads as null, not as an error', () {
    expect(VmReader.readClass(card, 'NoSuchVm'), isNull);
  });

  test('a class with a no-argument constructor is not a view-model', () {
    // Marker classes and private-constructor singletons live in the same
    // files as widgets. Accepting them would hand a preview generator a model
    // with nothing to draw.
    const markers = '''
class StyledSnackbar {
  StyledSnackbar._();
  static final instance = StyledSnackbar._();
}

class Sentinel {
  const Sentinel();
}
''';
    expect(VmReader.read(markers), isEmpty);
  });

  test('generic fields keep their type argument', () {
    const generic = '''
final class FieldVm<T> extends Equatable {
  const FieldVm({required this.value, this.error});

  final T value;
  final String? error;

  @override
  List<Object?> get props => [value, error];
}
''';
    final vm = read(generic, 'FieldVm');
    expect(field(vm, 'value').type, 'T');
    expect(field(vm, 'error').type, 'String?');
  });
}
