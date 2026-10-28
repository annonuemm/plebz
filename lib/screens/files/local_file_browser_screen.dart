import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../i18n/strings.g.dart';
import '../../services/local_file_access.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';

/// The app's own file browser, for boxes without the system's picker (fork
/// addition): the volumes first, then folder by folder, showing the folders
/// and the files of the types asked for. Choosing a file closes it with that
/// file's path.
///
/// Given [saveName] it chooses a folder instead: folders only, and "Save here"
/// on top, which hands the folder to [save] and closes with the path it wrote.
class LocalFileBrowserScreen extends StatefulWidget {
  const LocalFileBrowserScreen({
    super.key,
    required this.roots,
    required this.extensions,
    required this.title,
    this.initialDirectory,
    this.saveName,
    this.save,
  }) : assert((saveName == null) == (save == null));

  final List<StorageRoot> roots;

  /// Lower case, without the dot.
  final Set<String> extensions;
  final String title;

  /// Where to start, when it lies on one of [roots]; the volumes otherwise.
  final String? initialDirectory;

  /// The name the file will be saved under — set, the browser chooses a folder.
  final String? saveName;

  /// Writes the file into the chosen folder and answers with its path.
  final Future<String> Function(String directory)? save;

  static Route<String> route({
    required List<StorageRoot> roots,
    required Set<String> extensions,
    required String title,
    String? initialDirectory,
    String? saveName,
    Future<String> Function(String directory)? save,
  }) => MaterialPageRoute<String>(
    builder: (_) => LocalFileBrowserScreen(
      roots: roots,
      extensions: extensions,
      title: title,
      initialDirectory: initialDirectory,
      saveName: saveName,
      save: save,
    ),
  );

  @override
  State<LocalFileBrowserScreen> createState() => _LocalFileBrowserScreenState();
}

class _LocalFileBrowserScreenState extends State<LocalFileBrowserScreen> {
  /// Null while the volumes are on show.
  String? _directory;
  List<FileSystemEntity> _entries = const [];
  bool _unreadable = false;
  bool _saving = false;

  bool get _choosingFolder => widget.saveName != null;

  @override
  void initState() {
    super.initState();
    final start = widget.initialDirectory;
    if (start != null && widget.roots.any((root) => start == root.path || p.isWithin(root.path, start))) {
      _open(start);
    } else if (widget.roots.length == 1) {
      // One volume, nothing to choose between: straight into it.
      _open(widget.roots.single.path);
    }
  }

  StorageRoot? get _root => widget.roots.where((root) => _within(root.path)).firstOrNull;

  bool _within(String root) {
    final dir = _directory;
    return dir != null && (dir == root || p.isWithin(root, dir));
  }

  void _open(String? directory) {
    if (directory == null) {
      setState(() {
        _directory = null;
        _entries = const [];
        _unreadable = false;
      });
      return;
    }
    List<FileSystemEntity> entries;
    var unreadable = false;
    try {
      entries = Directory(directory).listSync(followLinks: false).where((entity) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) return false;
        if (entity is Directory) return true;
        if (entity is! File || _choosingFolder) return false;
        final ext = p.extension(name).toLowerCase();
        return ext.isNotEmpty && widget.extensions.contains(ext.substring(1));
      }).toList();
      entries.sort((a, b) {
        final byKind = (a is Directory ? 0 : 1).compareTo(b is Directory ? 0 : 1);
        return byKind != 0 ? byKind : p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
    } catch (_) {
      entries = const [];
      unreadable = true;
    }
    setState(() {
      _directory = directory;
      _entries = entries;
      _unreadable = unreadable;
    });
  }

  /// One level up; from a volume's root back to the volumes, or out when there
  /// is only one.
  void _up() {
    final dir = _directory;
    final root = _root;
    if (dir == null) return;
    if (root == null || dir == root.path) {
      if (widget.roots.length == 1) {
        Navigator.of(context).pop();
      } else {
        _open(null);
      }
      return;
    }
    _open(p.dirname(dir));
  }

  Future<void> _saveHere() async {
    final dir = _directory;
    final save = widget.save;
    if (dir == null || save == null || _saving) return;
    _saving = true;
    try {
      final path = await save(dir);
      if (mounted) Navigator.of(context).pop(path);
    } catch (_) {
      // A stick that is read-only, a folder the system keeps to itself: the
      // viewer picks another, the browser stays where it is.
      if (mounted) await showFullTextDialog(context, title: widget.title, text: t.localFiles.saveFailed);
    } finally {
      _saving = false;
    }
  }

  String get _location {
    final dir = _directory;
    final root = _root;
    if (dir == null) return t.localFiles.volumes;
    if (root == null) return dir;
    final inside = p.relative(dir, from: root.path);
    return inside == '.' ? root.label : '${root.label}/$inside';
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7));
    final atVolumes = _directory == null;
    return PopScope(
      // BACK climbs the folders before it leaves the browser.
      canPop: atVolumes || (widget.roots.length == 1 && _root?.path == _directory),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: FocusedScrollScaffold(
        title: Text(widget.title),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(_location, style: muted),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              if (atVolumes)
                for (final root in widget.roots)
                  FocusableListTile(
                    leading: AppIcon(root.removable ? Symbols.usb_rounded : Symbols.hard_drive_rounded, fill: 1),
                    title: Text(root.label),
                    subtitle: Text(root.path),
                    onTap: () => _open(root.path),
                  )
              else ...[
                if (_choosingFolder && !_unreadable)
                  FocusableListTile(
                    leading: const AppIcon(Symbols.save_rounded, fill: 1),
                    title: Text(t.localFiles.saveHere),
                    subtitle: Text(widget.saveName!),
                    onTap: _saveHere,
                  ),
                FocusableListTile(
                  leading: const AppIcon(Symbols.arrow_upward_rounded, fill: 1),
                  title: Text(t.localFiles.up),
                  onTap: _up,
                ),
                for (final entity in _entries)
                  entity is Directory
                      ? FocusableListTile(
                          leading: const AppIcon(Symbols.folder_rounded, fill: 1),
                          title: Text(p.basename(entity.path)),
                          onTap: () => _open(entity.path),
                        )
                      : FocusableListTile(
                          leading: const AppIcon(Symbols.description_rounded, fill: 1),
                          title: Text(p.basename(entity.path)),
                          onTap: () => Navigator.of(context).pop(entity.path),
                        ),
              ],
              if (atVolumes && widget.roots.isEmpty) _note(t.localFiles.noVolumes, muted),
              if (!atVolumes && _unreadable) _note(t.localFiles.unreadable, muted),
              if (!atVolumes && !_unreadable && _entries.isEmpty && !_choosingFolder)
                _note(t.localFiles.nothingHere(types: widget.extensions.map((e) => '.$e').join(', ')), muted),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _note(String text, TextStyle? style) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(text, style: style),
  );
}
