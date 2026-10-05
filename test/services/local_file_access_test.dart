import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/files/local_file_browser_screen.dart';
import 'package:plezy/services/file_picker_service.dart';
import 'package:plezy/services/local_file_access.dart';
import 'package:plezy/theme/mono_theme.dart';

class _Picker implements FilePickerDelegate {
  _Picker(this.path);

  final String? path;

  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool withData = false,
  }) async => path == null ? null : FilePickerResult([PlatformFile(name: path!.split('/').last, size: 1, path: path)]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A button that asks [LocalFileAccess.pickFile] and shows what came back.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String result = 'none';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () async {
            final path = await LocalFileAccess.pickFile(context, extensions: const {'m3u', 'm3u8'}, title: 'Pick');
            setState(() => result = path ?? 'nothing');
          },
          child: const Text('pick'),
        ),
        Text('result: $result'),
      ],
    ),
  );
}

void main() {
  late Directory root;

  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() {
    root = Directory.systemTemp.createTempSync('plebz_files');
    Directory('${root.path}/Listen').createSync();
    File('${root.path}/Listen/sender.m3u').writeAsStringSync('#EXTM3U');
    File('${root.path}/Listen/notes.txt').writeAsStringSync('x');
    File('${root.path}/Listen/.hidden.m3u').writeAsStringSync('#EXTM3U');
  });

  tearDown(() {
    LocalFileAccess.debugChannel = null;
    FilePickerService.setDelegateForTesting(null);
    root.deleteSync(recursive: true);
  });

  Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(theme: monoTheme(dark: true), home: const _Host()),
    ),
  );

  testWidgets('the browser walks folders, shows only the asked-for files, and hands back the chosen one', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await Navigator.of(context).push(
                  LocalFileBrowserScreen.route(
                    roots: [StorageRoot(path: root.path, label: 'Intern', removable: false)],
                    extensions: const {'m3u', 'm3u8'},
                    title: 'Pick',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // One volume: straight into it.
    expect(find.text('Listen'), findsOneWidget);
    await tester.tap(find.text('Listen'));
    await tester.pumpAndSettle();

    expect(find.text('sender.m3u'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing, reason: 'not a playlist');
    expect(find.text('.hidden.m3u'), findsNothing, reason: 'hidden');

    await tester.tap(find.text(t.localFiles.up));
    await tester.pumpAndSettle();
    expect(find.text('Listen'), findsOneWidget, reason: 'back at the volume root');

    await tester.tap(find.text('Listen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sender.m3u'));
    await tester.pumpAndSettle();
    expect(chosen, '${root.path}/Listen/sender.m3u');
  });

  testWidgets('where the box has a picker, it is used and no access is asked for', (tester) async {
    final asked = <String>[];
    LocalFileAccess.debugChannel = (method) async {
      asked.add(method);
      return method == 'hasDocumentPicker';
    };
    FilePickerService.setDelegateForTesting(_Picker('/somewhere/list.M3U'));
    await pumpHost(tester);

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(find.text('result: /somewhere/list.M3U'), findsOneWidget);
    expect(asked, ['hasDocumentPicker']);
  });

  testWidgets('a file of another type from the picker is turned away with a word', (tester) async {
    LocalFileAccess.debugChannel = (method) async => method == 'hasDocumentPicker';
    FilePickerService.setDelegateForTesting(_Picker('/somewhere/photo.jpg'));
    await pumpHost(tester);

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(find.text(t.localFiles.wrongTypeTitle), findsOneWidget);
  });

  testWidgets('without a picker the access is asked for once, then the browser opens', (tester) async {
    var granted = false;
    final asked = <String>[];
    LocalFileAccess.debugChannel = (method) async {
      asked.add(method);
      switch (method) {
        case 'hasDocumentPicker':
          return false;
        case 'hasFileAccess':
          return granted;
        case 'requestFileAccess':
          granted = true;
          return true;
        case 'storageRoots':
          return [
            {'path': root.path, 'label': 'Intern', 'removable': false},
          ];
      }
      return null;
    };
    await pumpHost(tester);

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(find.text(t.localFiles.accessTitle), findsOneWidget);

    await tester.tap(find.text(t.localFiles.accessConfirm));
    await tester.pumpAndSettle();
    expect(asked, contains('requestFileAccess'));
    expect(find.byType(LocalFileBrowserScreen), findsOneWidget);

    await tester.tap(find.text('Listen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sender.m3u'));
    await tester.pumpAndSettle();
    expect(find.text('result: ${root.path}/Listen/sender.m3u'), findsOneWidget);
  });

  testWidgets('a box with no screen for the access says how to grant it', (tester) async {
    LocalFileAccess.debugChannel = (method) async => switch (method) {
      'requestFileAccess' => false,
      _ => false,
    };
    await pumpHost(tester);

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.localFiles.accessConfirm));
    await tester.pumpAndSettle();

    expect(find.textContaining('adb shell appops set app.plebz MANAGE_EXTERNAL_STORAGE allow'), findsOneWidget);
    expect(find.byType(LocalFileBrowserScreen), findsNothing);
  });
}
