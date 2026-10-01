# Changelog

The English notes for each Plebz release; they are the text of its GitHub
release. The app shows the same notes in German (`assets/whats_new.md`).
One section per version, newest first, headed `## <version> (Build <build>)`.

## 1.3.0 (Build 572)

**Plebz 1.3.0 is a security update.**

### Remote control
- A phone now has to be paired once, with an eight-digit code shown on the device it controls. Until now the same account was enough, and the key could be worked out from server data anyone could fetch.
- Pairing uses CPace: the code can neither be overheard nor guessed by trying. Paired phones stay paired and can be removed in the remote control window.
- Connections from a web browser are refused, so no web page in the home network can reach the remote control.
- **Important:** the phone and the controlled device both need this version.

### Credentials and connections
- Trakt and MDBList sign-ins, IPTV passwords and playlist addresses, and the Seerr session are stored encrypted. On Android, the key for them lives in the Android Keystore.
- Android no longer puts the app's data into Google's automatic backup. To move to a new device, use the app's own password-protected backup under All settings → Backup.
- Backups protect their password more strongly. Older backups can still be restored.
- Jellyfin, Emby and Seerr servers on the internet: entered without "https://", Plebz now only tries encrypted connections. Unencrypted HTTP to the internet only happens after a warning.
- Logs now also hide user names, IPTV addresses and server addresses in error messages.

### Playback and files
- The built-in FFmpeg library is updated to version 8.0.3. It closes security holes that a crafted stream or file could exploit.
- IPTV: playlists and guide data are read only up to 256 MB. A broken or deliberately bloated file can no longer crash the app.
- Downloads: a server can no longer have files stored outside the download folder.
- External players only receive downloaded files, nothing else from the app's storage.
