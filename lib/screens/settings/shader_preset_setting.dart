import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../models/shader_preset.dart';
import '../../providers/shader_provider.dart';
import '../../services/settings_service.dart';
import '../../services/shader_service.dart';
import 'settings_utils.dart' show DialogOption;
import '../../widgets/setting_tile.dart';

/// The shader the mpv player starts with, chosen outside the player.
///
/// Until now it could only be picked in the player's own sheet — and a shader
/// too heavy for the device stutters the picture so badly that the sheet can
/// hardly be reached to take it back. The same saved preset the player
/// applies: [SettingsService.globalShaderPreset]. Null where the platform has
/// no shaders (iOS).
Widget? shaderPresetSettingTile(BuildContext context) {
  if (!ShaderService.isPlatformSupported) return null;
  // ExoPlayer has no shaders; the choice would do nothing there.
  if (Platform.isAndroid && SettingsService.instance.read(SettingsService.useExoPlayer)) return null;
  final provider = context.watch<ShaderProvider?>();
  final presets = provider?.allPresets ?? ShaderPreset.allPresets;
  String label(String id) {
    final preset = provider?.findPresetById(id) ?? ShaderPreset.fromId(id) ?? ShaderPreset.none;
    return shaderPresetLabel(preset);
  }

  return SettingSelectionTile<String>(
    pref: SettingsService.globalShaderPreset,
    icon: Symbols.auto_fix_high_rounded,
    title: t.shaders.title,
    subtitleBuilder: label,
    options: [
      DialogOption(value: ShaderPreset.none.id, title: label(ShaderPreset.none.id)),
      for (final preset in presets)
        if (preset.type != ShaderPresetType.none) DialogOption(value: preset.id, title: label(preset.id)),
    ],
  );
}

/// A preset's name as the player's sheet writes it: "Aus" for none, the
/// built-in families with their translated variant and quality words.
String shaderPresetLabel(ShaderPreset preset) => switch (preset.type) {
  ShaderPresetType.none => t.common.off,
  ShaderPresetType.artcnn => switch (preset.artcnnConfig) {
    null => preset.name,
    final config when config.variant == ArtCNNVariant.neutral => 'ArtCNN ${config.model.label}',
    final config =>
      'ArtCNN ${config.model.label} ${switch (config.variant) {
        ArtCNNVariant.neutral => t.shaders.artcnnVariantNeutral,
        ArtCNNVariant.denoise => t.shaders.artcnnVariantDenoise,
        ArtCNNVariant.denoiseSharpen => t.shaders.artcnnVariantDenoiseSharpen,
      }}',
  },
  ShaderPresetType.anime4k => switch (preset.anime4kConfig) {
    null => preset.name,
    final config =>
      'Anime4K ${config.quality == Anime4KQuality.fast ? t.shaders.qualityFast : t.shaders.qualityHQ} '
          '${config.mode.label}',
  },
  ShaderPresetType.nvscaler || ShaderPresetType.custom => preset.name,
};
