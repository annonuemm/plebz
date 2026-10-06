import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/trackers/tracker_constants.dart';

/// What this fork calls itself on the About page and in its license entry.
/// The translations carry the same name (`t.app.title` and the texts that name
/// the app); what the app tells Plex and Jellyfin stays "Plezy" on purpose —
/// servers would otherwise take it for a new, unknown device.
const forkAppName = 'Plebz';

/// The Plezy release this build is merged up to. Plebz numbers its own versions
/// (pubspec), so this is where the base is named — About shows it, and
/// `scripts/publish_public.sh` puts it in every public commit. Set it at each
/// upstream merge.
const upstreamBaseVersion = '2.22.0';

/// Where Plebz publishes its releases, as "owner/repository" on GitHub.
/// Releases carry the arm32 and arm64 APKs `scripts/build_apk.sh` names; an
/// x86_64 device finds no file for itself and says so.
const plebzReleaseRepository = 'annonuemm/plebz';

/// Whether this build can update itself: Android only (the Mac build is
/// private), and only once there is a repository to ask.
bool get plebzUpdatesAvailable =>
    debugPlebzUpdatesAvailable ?? (Platform.isAndroid && plebzReleaseRepository.isNotEmpty);

@visibleForTesting
bool? debugPlebzUpdatesAvailable;

/// TMDB's required attribution, word for word, for apps that show its data.
const tmdbAttributionNotice = 'This product uses the TMDB API but is not endorsed or certified by TMDB.';

/// Watch Together, the log upload and Discord's poster all go through one
/// host, `ice.plezy.app`, which belongs to Plezy's developer. This fork runs
/// none of its own, so the three stay switched off rather than send viewers'
/// sessions, logs and posters to someone else's server.
///
/// Getters rather than constants so the code they guard is not dead code.
bool get watchTogetherAvailable => debugPlezyHostedServicesAvailable;
bool get logUploadAvailable => debugPlezyHostedServicesAvailable;
bool get discordPosterUploadAvailable => debugPlezyHostedServicesAvailable;

/// Discord's rich presence, removed at the user's word (2026-10-02): the
/// settings don't offer it and the service never starts. A desktop feature to
/// begin with; the code stays for upstream merges.
bool get discordRichPresenceAvailable => debugDiscordRichPresenceAvailable;

/// Lets upstream's Discord tests keep running.
@visibleForTesting
bool debugDiscordRichPresenceAvailable = false;

/// Lets upstream's tests keep exercising the code behind those three switches.
@visibleForTesting
bool debugPlezyHostedServicesAvailable = false;

/// MyAnimeList and AniList sign in through the same host's OAuth proxy
/// (`ice.plezy.app/auth`), and MAL identifies itself with the app id Plezy
/// registered. This fork leaves them out: settings don't offer them, and a
/// session stored before is not loaded, so nothing talks to them on Plezy's
/// credentials — no scrobbling, no Explore or watchlist tab. The stored
/// session stays on disk untouched.
///
/// Trakt and MDBList went the same way on 2026-10-02 at the user's word: not
/// used, and Trakt's sign-in, like MDBList's, runs on the app ids Plezy
/// registered.
///
/// Simkl came back on 2026-10-06 at the user's word, as the tracker a profile
/// can keep its own progress in. It signs in with a PIN straight at Simkl —
/// no relay page on Plezy's host — and still on the app id Plezy registered,
/// which the user accepted; an own id is one constant in `simkl_constants.dart`.
const forkRemovedTrackers = {TrackerService.mal, TrackerService.anilist, TrackerService.trakt, TrackerService.mdblist};

bool isTrackerAvailable(TrackerService service) =>
    debugRemovedTrackersAvailable || !forkRemovedTrackers.contains(service);

/// Upstream's tracker tests exercise the shared session machinery through these
/// three services; they switch this on so that coverage keeps running.
@visibleForTesting
bool debugRemovedTrackersAvailable = false;

/// The app's own license — the repository's GPL-3.0 text, bundled as an asset
/// — listed under "Open-source licenses" beside the libraries', so a television
/// without a browser can still show it.
void registerForkLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('LICENSE');
    yield LicenseEntryWithLineBreaks(const [forkAppName], text);
  });
}
