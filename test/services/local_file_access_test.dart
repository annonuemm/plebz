import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/files/local_file_browser_screen.dart';
import 'package:plezy/services/file_picker_service.dart';
import 'package:plezy/services/local_file_access.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';

class _Picker implements FilePickerDelegate {
  _Picker(this.path);

  final String? path;

  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool withData = false,
  }) async => path == null ? null : FilePickerResult([PlatformFile(name: path!.split('/').last, size: 1, path: path)]);

  String? savedName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    Uint8List? bytes,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    savedName = fileName;
    return path;
  }

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
            final save = await LocalFileAccess.saveFile(
              context,
              fileName: 'plebz-backup.json',
              bytes: Uint8List.fromList(utf8.encode('{}')),
              extension: 'json',
              title: 'Save',
            );
            setState(() => result = '${save.outcome.name} ${save.path}');
          },
          child: const Text('save'),
        ),
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
      child: MaterialApp(theme: monoTheme(MonoPalette.dark), home: const _Host()),
    ),
  );

  testWidgets('the browser walks folders, shows only the asked-for files, and hands back the chosen one', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark),
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

  testWidgets('saving: the browser starts where asked, shows folders only, and saves into the chosen one', (
    tester,
  ) async {
    String? saved;
    final written = <String>[];
    var failNext = false;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push(
                  LocalFileBrowserScreen.route(
                    roots: [StorageRoot(path: root.path, label: 'Intern', removable: false)],
                    extensions: const {'m3u'},
                    title: 'Save',
                    initialDirectory: '${root.path}/Listen',
                    saveName: 'plebz-backup.json',
                    save: (directory) async {
                      if (failNext) {
                        failNext = false;
                        throw const FileSystemException('read-only');
                      }
                      written.add(directory);
                      return '$directory/plebz-backup.json';
                    },
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

    expect(find.text('Intern/Listen'), findsOneWidget, reason: 'it starts in the folder it was given');
    expect(find.text('sender.m3u'), findsNothing, reason: 'choosing a folder, not a file');
    expect(find.text('plebz-backup.json'), findsOneWidget, reason: 'the name it will be saved under');

    failNext = true;
    await tester.tap(find.text(t.localFiles.saveHere));
    await tester.pumpAndSettle();
    expect(find.text(t.localFiles.saveFailed), findsOneWidget);
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(
      find.byType(LocalFileBrowserScreen),
      findsOneWidget,
      reason: 'a folder that refuses leaves the browser open',
    );

    await tester.tap(find.text(t.localFiles.up));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.localFiles.saveHere));
    await tester.pumpAndSettle();
    expect(written, [root.path]);
    expect(saved, '${root.path}/plebz-backup.json');
  });

  testWidgets('saving where the box can save with its picker uses it and asks for no access', (tester) async {
    final asked = <String>[];
    LocalFileAccess.debugChannel = (method) async {
      asked.add(method);
      return method == 'hasDocumentSaver';
    };
    final picker = _Picker('/picked/plebz-backup.json');
    FilePickerService.setDelegateForTesting(picker);
    await pumpHost(tester);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(find.text('result: saved /picked/plebz-backup.json'), findsOneWidget);
    expect(picker.savedName, 'plebz-backup.json');
    expect(asked, ['hasDocumentSaver']);
  });

  testWidgets('saving without a picker asks for write access, then writes where the browser was left', (tester) async {
    var granted = false;
    final asked = <String>[];
    final stick = Directory('${root.path}/stick')..createSync();
    Directory('${stick.path}/Download').createSync();
    LocalFileAccess.debugChannel = (method) async {
      asked.add(method);
      switch (method) {
        case 'hasWriteAccess':
          return granted;
        case 'requestFileAccess':
          granted = true;
          return true;
        case 'storageRoots':
          return [
            {'path': '${root.path}/Listen', 'label': 'Intern', 'removable': false},
            {'path': stick.path, 'label': 'USB', 'removable': true},
          ];
      }
      return false;
    };
    await pumpHost(tester);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.localFiles.accessConfirm));
    await tester.pumpAndSettle();

    expect(asked, containsAllInOrder(['hasDocumentSaver', 'hasWriteAccess', 'requestFileAccess']));
    expect(find.text('USB/Download'), findsOneWidget, reason: 'a stick first, and its Download folder');

    // A real write: it needs real time, not the test's fake clock.
    await tester.runAsync(() async {
      await tester.tap(find.text(t.localFiles.saveHere));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final file = File('${stick.path}/Download/plebz-backup.json');
    expect(file.readAsStringSync(), '{}');
    expect(find.text('result: saved ${file.path}'), findsOneWidget);
  });

  testWidgets('saving without a picker and without the access is left to the caller', (tester) async {
    LocalFileAccess.debugChannel = (method) async => false;
    await pumpHost(tester);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.localFiles.accessConfirm));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();

    expect(find.text('result: unavailable null'), findsOneWidget);
    expect(find.byType(LocalFileBrowserScreen), findsNothing);
  });

  test('saving starts on a removable volume, in its Download folder where there is one', () {
    final internal = Directory('${root.path}/internal')..createSync();
    Directory('${internal.path}/Download').createSync();
    final stick = Directory('${root.path}/stick')..createSync();
    final internalRoot = StorageRoot(path: internal.path, label: 'Intern', removable: false);
    final stickRoot = StorageRoot(path: stick.path, label: 'USB', removable: true);

    expect(LocalFileAccess.startFolder([internalRoot]), '${internal.path}/Download');
    expect(LocalFileAccess.startFolder([internalRoot, stickRoot]), stick.path, reason: 'the stick has no Download');
    Directory('${stick.path}/Download').createSync();
    expect(LocalFileAccess.startFolder([internalRoot, stickRoot]), '${stick.path}/Download');
    expect(LocalFileAccess.startFolder(const []), isNull);
  });

  testWidgets('Apple TV is offered no file at all: no picker, no access dialog, no browser', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final picker = _Picker('/somewhere/list.m3u');
    FilePickerService.setDelegateForTesting(picker);

    expect(LocalFileAccess.available, isFalse);
    expect(await LocalFileAccess.hasSystemPicker(), isFalse);

    await pumpHost(tester);
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(find.text('result: nothing'), findsOneWidget);
    expect(find.text(t.localFiles.accessTitle), findsNothing);
    expect(find.byType(LocalFileBrowserScreen), findsNothing);
  });
}
