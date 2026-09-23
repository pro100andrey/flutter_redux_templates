import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/ast/source_index.dart';
import 'package:tools/src/routing/tab_shell_source.dart';

/// The shell `add-tabs` writes, with [tabs] as its tabs.
String _shell(List<String> tabs, {List<String>? labels}) =>
    '''
@RoutePage()
class ShellPageConnector extends StatelessWidget {
  const ShellPageConnector({super.key});

  @override
  Widget build(BuildContext context) => AutoTabsScaffold(
    routes: const [${tabs.map((t) => '${t}Route()').join(', ')}],
    bottomNavigationBuilder: (_, tabsRouter) => BottomNavigationBar(
      currentIndex: tabsRouter.activeIndex,
      onTap: tabsRouter.setActiveIndex,
      items: const [
${(labels ?? tabs).map((l) => "        BottomNavigationBarItem(icon: Icon(Icons.circle_outlined), label: '$l'),").join('\n')}
      ],
    ),
  );
}
''';

TabShellSource _source(String content) {
  final dir = Directory.systemTemp.createTempSync('frx_tabs_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final f = File(p.join(dir.path, 'shell_page_connector.dart'))
    ..writeAsStringSync(content);
  return TabShellSource(f);
}

void main() {
  test('a tab leaves the routes and the bar at the same index', () {
    final out = inSourceIndex(
      () => _source(
        _shell(['News', 'Chat', 'Me']),
      ).withoutTab('ChatRoute'),
    );
    expect(out.found, isTrue);
    expect(
      out.source.replaceAll(' ', ''),
      contains('routes:const[NewsRoute(),MeRoute()]'),
      reason: 'the format pass tidies the gap the splice leaves',
    );
    expect(out.source, isNot(contains("label: 'Chat'")));
    expect(out.source, contains("label: 'News'"));
    expect(out.source, contains("label: 'Me'"));
  });

  test('a shell it would leave with one tab is left for its author', () {
    // `BottomNavigationBar` asserts on fewer than two items: one tab is not a
    // shell any more, and what replaces it is a decision, not an unwiring.
    final out = inSourceIndex(
      () => _source(_shell(['News', 'Me'])).withoutTab('MeRoute'),
    );
    expect(out.found, isFalse);
  });

  test('lists that disagree in length are left alone', () {
    // Dropping index i from both would drop the wrong bar item.
    final out = inSourceIndex(
      () => _source(
        _shell(['News', 'Chat', 'Me'], labels: ['News', 'Me']),
      ).withoutTab('ChatRoute'),
    );
    expect(out.found, isFalse);
  });

  test('a route the shell does not list is absent', () {
    final out = inSourceIndex(
      () => _source(_shell(['News', 'Chat', 'Me'])).withoutTab('FeedRoute'),
    );
    expect(out.found, isFalse);
  });
}
