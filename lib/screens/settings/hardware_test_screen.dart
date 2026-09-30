import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/hardware_report_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';

/// What the device says it can do.
///
/// Read afresh every time it is opened: an AV receiver switched on since the
/// last look, a television woken from standby or a changed system setting all
/// change the answer, and a remembered report would be a confident lie.
class HardwareTestScreen extends StatefulWidget {
  const HardwareTestScreen({super.key});

  @override
  State<HardwareTestScreen> createState() => _HardwareTestScreenState();
}

class _HardwareTestScreenState extends State<HardwareTestScreen> {
  List<HardwareSection>? _sections;
  bool _loading = true;

  static HardwareReportLabels get _labels {
    final sections = t.settings.hardwareTestSections;
    final labels = t.settings.hardwareTestLabels;
    return HardwareReportLabels(
      device: sections.device,
      display: sections.display,
      colour: sections.colour,
      audio: sections.audio,
      video: sections.video,
      model: labels.model,
      system: labels.system,
      architecture: labels.architecture,
      televisionMode: labels.televisionMode,
      currentMode: labels.currentMode,
      modeSwitching: labels.modeSwitching,
      displayMode: labels.displayMode,
      displayModes: labels.displayModes,
      hdrFormats: labels.hdrFormats,
      wideColour: labels.wideColour,
      peakBrightness: labels.peakBrightness,
      audioOutput: labels.audioOutput,
      channels: labels.channels,
      hardwareDecoder: labels.hardwareDecoder,
      noHardwareDecoder: labels.noHardwareDecoder,
      tunneling: labels.tunneling,
      possible: labels.possible,
      notPossible: labels.notPossible,
      unavailable: labels.unavailable,
      none: labels.none,
      yes: labels.yes,
      no: labels.no,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final report = await HardwareReportService.read();
    if (!mounted) return;
    setState(() {
      _sections = report == null ? null : HardwareReportService.sectionsFrom(report, _labels);
      _loading = false;
    });
  }

  Future<void> _copy() async {
    final sections = _sections;
    if (sections == null) return;
    await Clipboard.setData(ClipboardData(text: HardwareReportService.asText(sections)));
    if (mounted) showSuccessSnackBar(context, t.startup.detailsCopied);
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    // Every row on this page is a fact, not a control. Flutter's default
    // (traditional) navigation refuses focus to a ListTile with nothing to
    // tap, so on a remote there was nothing to move to: the list never
    // scrolled and the page ended at whatever fitted the screen — eight rows
    // of a report that runs to five sections. Directional navigation is the
    // mode written for D-pads. It lets a row take focus without a callback
    // *and* paints the same focus highlight the settings groups use as their
    // D-pad visual, so the reader can walk the report and it scrolls with
    // them. Scoped to this page: switching the whole app would make every
    // disabled control focusable too.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
      child: _buildPage(context, sections),
    );
  }

  Widget _buildPage(BuildContext context, List<HardwareSection>? sections) {
    return SettingsPage(
      title: Text(t.settings.hardwareTest),
      actions: [
        if (sections != null)
          IconButton(
            icon: const AppIcon(Symbols.content_copy_rounded, size: 20),
            tooltip: t.startup.copyDetails,
            onPressed: _copy,
          ),
      ],
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (sections == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.settings.hardwareTestUnavailable, textAlign: TextAlign.center),
          )
        else
          for (final section in sections)
            SettingsGroup(
              title: section.title,
              children: [
                for (final fact in section.facts)
                  FocusableListTile(
                    leading: fact.supported == null
                        ? const SizedBox(width: 24)
                        : AppIcon(
                            fact.supported! ? Symbols.check_circle_rounded : Symbols.cancel_rounded,
                            fill: 1,
                            color: fact.supported!
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    title: Text(fact.name),
                    trailing: Text(fact.value, style: Theme.of(context).textTheme.bodyMedium),
                  ),
              ],
            ),
      ],
    );
  }
}
