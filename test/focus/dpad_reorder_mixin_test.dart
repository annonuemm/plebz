import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/dpad_reorder_mixin.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';

class _ReorderHost extends StatefulWidget {
  const _ReorderHost();

  @override
  State<_ReorderHost> createState() => _ReorderHostState();
}

class _ReorderHostState extends State<_ReorderHost> with DpadReorderListMixin<String, _ReorderHost> {
  List<String> items = ['a', 'b', 'c', 'd'];
  final List<(int, int)> activations = [];
  int confirms = 0;

  @override
  List<String> get reorderItems => items;

  @override
  set reorderItems(List<String> value) => items = value;

  @override
  int get lastReorderColumn => 1;

  @override
  ScrollController? get reorderScrollController => null;

  @override
  void onReorderMoveConfirmed() => confirms++;

  @override
  void onReorderColumnActivated(int column, int index) {
    activations.add((column, index));
    setState(() => items.removeAt(index));
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

const _down = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.select,
  logicalKey: LogicalKeyboardKey.select,
  timeStamp: Duration.zero,
);
const _repeat = KeyRepeatEvent(
  physicalKey: PhysicalKeyboardKey.select,
  logicalKey: LogicalKeyboardKey.select,
  timeStamp: Duration.zero,
);
const _up = KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.select,
  logicalKey: LogicalKeyboardKey.select,
  timeStamp: Duration.zero,
);

void main() {
  final node = FocusNode();
  tearDownAll(node.dispose);

  Future<_ReorderHostState> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(const _ReorderHost());
    return tester.state<_ReorderHostState>(find.byType(_ReorderHost));
  }

  testWidgets('holding SELECT on an action column activates it once', (tester) async {
    final state = await pumpHost(tester);
    state.focusedColumn = 1;

    expect(state.handleReorderKeyEvent(node, _down), KeyEventResult.handled);
    for (var i = 0; i < 10; i++) {
      expect(state.handleReorderKeyEvent(node, _repeat), KeyEventResult.handled);
    }
    expect(state.handleReorderKeyEvent(node, _up), KeyEventResult.handled);

    expect(state.activations, [(1, 0)]);
    expect(state.items, ['b', 'c', 'd']);
  });

  testWidgets('holding SELECT on a row enters move mode without confirming it', (tester) async {
    final state = await pumpHost(tester);

    state.handleReorderKeyEvent(node, _down);
    for (var i = 0; i < 3; i++) {
      state.handleReorderKeyEvent(node, _repeat);
    }
    state.handleReorderKeyEvent(node, _up);

    expect(state.movingIndex, 0);
    expect(state.confirms, 0);

    state.handleReorderKeyEvent(node, _down);
    expect(state.movingIndex, isNull);
    expect(state.confirms, 1);
  });

  group('under glass', () {
    Future<void> pumpMarks(WidgetTester tester, {required AppThemeVariant variant, required bool focused}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Scaffold(
            body: DpadReorderRowMark(
              isMoving: false,
              isRowFocused: focused,
              child: ListTile(
                title: const Text('Filme'),
                trailing: DpadReorderButtonFocus(
                  isFocused: focused,
                  child: IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the cursor row and its buttons are marked with panes of glass', (tester) async {
      await pumpMarks(tester, variant: AppThemeVariant.glas, focused: true);

      expect(find.byType(OckerGlassFocusFill), findsNWidgets(2), reason: 'one behind the row, one behind the button');
      expect(
        dpadReorderRowColor(tester.element(find.text('Filme')), isMoving: false, isRowFocused: true),
        isNull,
        reason: 'no ink fill on top of the glass',
      );
    });

    testWidgets('elsewhere the row keeps its ink fill and the button its plate', (tester) async {
      await pumpMarks(tester, variant: AppThemeVariant.standard, focused: true);

      expect(find.byType(OckerGlassFocusFill), findsNothing);
      expect(dpadReorderRowColor(tester.element(find.text('Filme')), isMoving: false, isRowFocused: true), isNotNull);
    });
  });
}
