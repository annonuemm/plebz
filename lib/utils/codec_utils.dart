import '../i18n/strings.g.dart';

/// Utility class for codec-related operations.
///
/// Provides centralized codec name mappings, file extension lookups,
/// and display name formatting.
class CodecUtils {
  CodecUtils._();

  static String getSubtitleExtension(String? codec) {
    if (codec == null) return 'srt';

    switch (codec.toLowerCase()) {
      case 'subrip':
      case 'srt':
        return 'srt';
      case 'ass':
      case 'ssa':
        return 'ass';
      case 'webvtt':
      case 'vtt':
        return 'vtt';
      case 'mov_text':
        return 'srt';
      case 'pgs':
      case 'pgssub':
      case 'hdmv_pgs_subtitle':
        return 'sup';
      case 'dvd_subtitle':
      case 'dvdsub':
      case 'vobsub':
      case 'dvb_sub':
      case 'dvb_subtitle':
        return 'sub';
      default:
        return 'srt';
    }
  }

  static bool isTextSubtitleCodec(String? codec) {
    if (codec == null) return false;
    return switch (codec.toLowerCase()) {
      'srt' || 'subrip' || 'ass' || 'ssa' || 'webvtt' || 'vtt' || 'mov_text' => true,
      _ => false,
    };
  }

  /// Image-based (bitmap) subtitle codecs. Plex burns these into the video
  /// when the selected output transport cannot carry a bitmap subtitle
  /// rendition.
  static bool isImageSubtitleCodec(String? codec) {
    if (codec == null) return false;
    return switch (codec.toLowerCase()) {
      'pgs' ||
      'pgssub' ||
      'hdmv_pgs_subtitle' ||
      'dvd_subtitle' ||
      'dvdsub' ||
      'vobsub' ||
      'dvb_sub' ||
      // Jellyfin's own spelling, which is what the transcode profile asks it to burn.
      'dvbsub' ||
      'dvb_subtitle' => true,
      _ => false,
    };
  }

  /// Subtitle codecs Plex can deliver in a transcode. Text codecs can become
  /// segmented HLS WebVTT; image codecs can be burned into the video.
  static bool isTranscodableSubtitleCodec(String? codec) {
    return isTextSubtitleCodec(codec) || isImageSubtitleCodec(codec);
  }

  /// Formats a subtitle codec name to a user-friendly display format.
  ///
  /// Converts internal codec names like 'SUBRIP' to friendly names like 'SRT'.
  static String formatSubtitleCodec(String codec) {
    final upper = codec.toUpperCase();
    return switch (upper) {
      'SUBRIP' => 'SRT',
      'DVD_SUBTITLE' => 'DVD',
      'WEBVTT' => 'VTT',
      'HDMV_PGS_SUBTITLE' => 'PGS',
      'MOV_TEXT' => 'MOV',
      _ => upper,
    };
  }

  /// Formats a video codec name to a user-friendly display format.
  ///
  /// Converts internal codec names like 'hevc' to friendly names like 'HEVC'.
  static String formatVideoCodec(String codec) {
    final lower = codec.toLowerCase();
    return switch (lower) {
      'h264' || 'avc1' || 'avc' => 'H.264',
      'hevc' || 'h265' || 'hev1' => 'HEVC',
      'av1' => 'AV1',
      'vp8' => 'VP8',
      'vp9' => 'VP9',
      'mpeg2video' || 'mpeg2' => 'MPEG-2',
      'mpeg4' => 'MPEG-4',
      'vc1' => 'VC-1',
      _ => codec.toUpperCase(),
    };
  }

  /// Formats an audio channel count as a friendly layout name (2 → 'Stereo',
  /// 6 → '5.1'). Returns null when [channels] is null or not positive.
  static String? formatAudioChannels(int? channels) {
    if (channels == null || channels <= 0) return null;
    return switch (channels) {
      1 => t.fileInfo.channelsMono,
      2 => t.videoSettings.audioOutputStereo,
      3 => '3.0',
      4 => '4.0',
      5 => '4.1',
      6 => '5.1',
      7 => '6.1',
      8 => '7.1',
      _ => '${channels}ch',
    };
  }

  /// Formats an audio codec name to a user-friendly display format.
  ///
  /// Formats an audio codec name, refined by the server's stream profile.
  ///
  /// Accepts ffmpeg-style names as reported by mpv and the media
  /// servers ('aac', 'eac3'), RFC 6381 codec IDs as reported by
  /// ExoPlayer's `Format.codecs` ('mp4a.40.2', 'ec-3', 'dtsc'), and
  /// `audio/...` MIME types as reported by ExoPlayer's
  /// `Format.sampleMimeType` ('audio/eac3', 'audio/vnd.dts').
  ///
  /// Both backends report a DTS-HD MA track as codec `dts` (older Plex servers
  /// as `dca`) and put the variant in a separate profile field, so the codec
  /// on its own calls every DTS flavour "DTS". [profile] takes either
  /// spelling — Jellyfin writes it out ("DTS-HD MA"), Plex abbreviates ("ma").
  static String formatAudioCodec(String codec, {String? profile}) {
    final lower = codec.toLowerCase();
    if (lower.startsWith('audio/')) {
      return switch (lower.substring('audio/'.length)) {
        'mp4a-latm' => 'AAC',
        'mpeg' || 'mpeg-l2' => 'MP3',
        'true-hd' => 'TrueHD',
        'vnd.dts' => 'DTS',
        'vnd.dts.hd' || 'vnd.dts.hd;profile=lbr' => 'DTS-HD',
        'vnd.dts.uhd;audio=p2' => 'DTS:X',
        'ac3' => 'AC3',
        'eac3' || 'eac3-joc' => 'E-AC3',
        'ac4' => 'AC4',
        'raw' || 'wav' => 'PCM',
        'alac' => 'ALAC',
        final rest => formatAudioCodec(rest),
      };
    }
    // MP4 object types 0x69/0x6B under the mp4a prefix are MPEG layer
    // audio; every other mp4a object type in the wild is an AAC variant.
    if (lower == 'mp4a.69' || lower == 'mp4a.6b') return 'MP3';
    if (lower == 'mp4a' || lower.startsWith('mp4a.')) return 'AAC';
    if (lower == 'ac-4' || lower.startsWith('ac-4.')) return 'AC4';
    return switch (lower) {
      'aac' => 'AAC',
      'ac3' || 'ac-3' => 'AC3',
      'eac3' || 'ec3' || 'ec-3' => 'E-AC3',
      'truehd' || 'mlpa' => 'TrueHD',
      // The bare family name; a profile, when there is one, sharpens it below.
      'dts' || 'dca' || 'dtsc' || 'dtse' || 'audio/vnd.dts' => _dtsName(profile) ?? 'DTS',
      'dtshd' || 'dts-hd' || 'dtsh' || 'dtsl' || 'audio/vnd.dts.hd' => _dtsName(profile) ?? 'DTS-HD',
      'dtsx' || 'audio/vnd.dts.uhd' => 'DTS:X',
      'flac' => 'FLAC',
      'mp3' || 'mp3float' => 'MP3',
      'opus' => 'Opus',
      'vorbis' => 'Vorbis',
      'pcm_s16le' || 'pcm_s24le' || 'pcm' => 'PCM',
      // Not every server keeps the variant in the profile field: some fold it
      // into the codec string itself ('dca-ma', 'dts-hd-ma') and leave the
      // profile empty, so the name has to come out of the codec.
      _ => _dtsNameFromCodec(lower) ?? codec.toUpperCase(),
    };
  }

  /// The DTS variant a compound codec string carries, or null when it carries
  /// none. Read whole first ('dts-hd-ma'), then behind the family prefix
  /// ('dca-ma'), which is the spelling [_dtsName] cannot normalize on its own.
  static String? _dtsNameFromCodec(String lower) {
    if (!lower.startsWith('dts') && !lower.startsWith('dca')) return null;
    final suffix = lower.replaceFirst(RegExp('^(?:dts|dca)[-_ ]'), '');
    return _dtsName(lower) ?? (suffix == lower ? null : _dtsName(suffix));
  }

  /// The DTS variant a stream profile names, or null when it names none.
  ///
  /// Plex sends the short form off the bitstream (`ma`, `hra`, `es`), Jellyfin
  /// the marketing name. Values that only repeat the family (`dts`, `dca`)
  /// carry no extra information and are left to the caller's default.
  static String? _dtsName(String? profile) {
    final key = profile?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (key == null || key.isEmpty) return null;
    return switch (key) {
      'ma' || 'dtshdma' || 'dtshdmasteraudio' => 'DTS-HD MA',
      'hra' || 'dtshdhra' || 'dtshdhighresolutionaudio' => 'DTS-HD HRA',
      'es' || 'dtses' || 'dtsesmatrix' || 'dtsesdiscrete' => 'DTS-ES',
      'x' || 'dtsx' || 'dtshdx' || 'dtsuhd' => 'DTS:X',
      'lbr' || 'express' || 'dtsexpress' => 'DTS Express',
      'dtshd' => 'DTS-HD',
      _ => null,
    };
  }
}
