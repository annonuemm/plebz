# Was ist neu in Plebz

<!--
The notes Plebz shows after an update, in the update dialog and under
Settings → "Was ist neu". One section per version, newest first:

  ## 1.2.0 (Build 559)
  - Item
  ### Subheading
  **bold** works too.

Only the build number in the heading makes a section visible; a draft
without one stays hidden in the app. The GitHub release carries the English
notes from CHANGELOG.md, with this German section hidden behind them in an
HTML comment; the app's update dialog shows that German part
(scripts/whats_new_section.py --release-body).
-->

## 1.3.0 (Build 572)

**Plebz 1.3.0 ist ein Sicherheits-Update.**

### Fernbedienung
- Ein Handy muss jetzt einmal mit einem achtstelligen Code gekoppelt werden, den das gesteuerte Gerät anzeigt. Bisher reichte dasselbe Konto, und der Schlüssel ließ sich aus öffentlich abrufbaren Server-Daten berechnen.
- Die Kopplung läuft über CPace: Der Code kann weder mitgehört noch durchprobiert werden. Gekoppelte Handys bleiben gekoppelt und lassen sich im Fernbedienungs-Fenster entfernen.
- Verbindungen aus einem Webbrowser werden abgelehnt, damit keine Webseite im Heimnetz die Fernbedienung erreicht.
- **Wichtig:** Handy und gesteuertes Gerät brauchen beide diese Version.

### Zugangsdaten und Verbindungen
- Trakt- und MDBList-Anmeldungen, IPTV-Passwörter und Playlist-Adressen sowie die Seerr-Sitzung werden verschlüsselt gespeichert. Auf Android liegt der Schlüssel dafür im Android-Keystore.
- Android nimmt die App-Daten nicht mehr in die automatische Google-Sicherung auf. Für einen Geräteumzug gibt es die eigene, passwortgeschützte Sicherung unter Alle Einstellungen → Sicherung.
- Sicherungen schützen ihr Passwort stärker. Ältere Sicherungen lassen sich weiter einlesen.
- Jellyfin-, Emby- und Seerr-Server im Internet: Ohne „https://“ eingetragen, versucht Plebz nur noch verschlüsselte Verbindungen. Unverschlüsseltes HTTP ins Internet gibt es nur noch nach einer Warnung.
- Protokolle verbergen jetzt auch Benutzernamen, IPTV-Adressen und Serveradressen in Fehlermeldungen.

### Wiedergabe und Dateien
- Die eingebaute FFmpeg-Bibliothek ist auf Version 8.0.3 aktualisiert. Sie schließt Sicherheitslücken, die ein präparierter Stream oder eine präparierte Datei ausnutzen könnte.
- IPTV: Playlisten und EPG-Daten werden nur noch bis 256 MB gelesen. Eine fehlerhafte oder absichtlich aufgeblähte Datei bringt die App so nicht mehr zum Absturz.
- Downloads: Ein Server kann Dateien nicht mehr außerhalb des Download-Ordners ablegen lassen.
- Externe Player bekommen nur noch heruntergeladene Dateien, nichts anderes aus dem Speicher der App.

## 1.2.3 (Build 567)

- EPG: OK lange gedrückt auf einem Senderlogo öffnet jetzt wirklich das Menü mit Favorit, Umbenennen und Ausblenden. Bisher hat der noch gehaltene Knopf gleich den ersten Eintrag gewählt und den Sender direkt zu den Favoriten gelegt. Dasselbe gilt für das Menü einer Gruppe.

## 1.2.2 (Build 565)

- EPG: OK auf einem Senderlogo zeigt den Sender wieder erst in der Vorschau, erst der zweite Druck öffnet ihn im Vollbild.

## 1.2.1 (Build 563)

- „Jetzt live“: Der Fokusrahmen einer Kachel wird nicht mehr von der Kachel daneben abgeschnitten.

## 1.2.0 (Build 561)

- Ein Sender aus „Jetzt live“ startet weiter im Vollbild, dahinter öffnet sich aber Live TV mit seiner Gruppe. Wer den Player verlässt, landet im EPG auf diesem Sender statt auf der Startseite.
- Neu: „Was ist neu“. Nach einem Update zeigt Plebz, was sich geändert hat, auch über übersprungene Versionen hinweg. Dieselben Notizen stehen im Update-Dialog und unter Einstellungen → „Was ist neu“.
