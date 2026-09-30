# LocalMusic

Eine lokale iOS-Musikbibliothek für eigene Dateien. V1 nutzt SwiftUI, SwiftData und AVFoundation und benötigt weder Account noch Cloud noch Backend.

## Aktueller Funktionsumfang

- iOS 17+ mit Home, Suche und Bibliothek
- Auswahl von Audiodateien und kompatiblen MP4-Dateien über die Dateien-App
- Import nach `Application Support/ImportedAudio` in den privaten, persistenten App-Speicher
- Metadaten (Titel, Künstler, Album, Dauer und Artwork), wenn in der Datei vorhanden; verständliche Fallbacks sonst
- SwiftData-basierte lokale Bibliothek
- Song antippen: Wiedergabe starten; Mini-Player mit Play/Pause
- Vollbild-Player durch Antippen des Mini-Players, mit Artwork, Fortschritt und ±15-Sekunden-Sprüngen
- Wiedergabe läuft im Hintergrund weiter, solange die App nicht über den App-Umschalter beendet wird
- Import- und Wiedergabefehler werden in der Oberfläche angezeigt

## Windows → GitHub → IPA

1. Erstelle auf GitHub ein leeres Repository und füge es als `origin` hinzu:

   ```powershell
   git remote add origin https://github.com/DEIN-NAME/DEIN-REPOSITORY.git
   git push -u origin main
   ```

2. Öffne auf GitHub den Reiter **Actions** und wähle **Build unsigned IPA**. Der Workflow startet bei jedem Push nach `main`, der eine App-, Projekt- oder Workflow-Datei ändert, und kann auch mit **Run workflow** manuell gestartet werden.
3. Der Job baut zuerst für den iOS-Simulator, führt die Unit-Tests aus und erstellt anschließend eine nicht signierte Device-App.
4. Lade nach einem erfolgreichen Lauf unter **Artifacts** `LocalMusic-unsigned-ipa` herunter. Darin liegt `LocalMusic-unsigned.ipa` für deinen bisherigen Sideloading-/Signier-Schritt.

Die IPA ist bewusst **nicht** direkt installierbar: Ohne Apple-Zertifikat und Provisioning Profile kann GitHub keine auf einem iPhone gültig signierte App erzeugen. Für eine später direkt installierbare IPA können ein Zertifikat und ein Provisioning Profile als GitHub Secrets ergänzt werden.

## Lokal auf Windows

Das Xcode-Projekt ist vollständig eingecheckt. Windows kann es bequem bearbeiten, aber die zuverlässige Kompilierung findet auf dem macOS-Runner von GitHub Actions statt. Lokale Build-Ordner und Signing-Dateien werden nicht eingecheckt.

## Metadaten und Reparatur alter Imports

Der Import sichert `originalFileName` direkt von der ausgewählten Quelle vor dem Kopieren.
Ist die Quell-URL selbst UUID-basiert, werden auch der Ressourcenname und lokalisierte Name
des Dateianbieters geprüft, solange der Security-Scope offen ist.
Nur die private Speicherdatei und Song-ID bleiben UUID-basiert. Der externe URL-Zugriff wird
mit `startAccessingSecurityScopedResource()`/`defer` begrenzt; für Wiedergabe wird ausschließlich
die persistente Kopie verwendet.

Jedes Feld wird unabhängig aufgelöst: brauchbare eingebettete Common-/ID3-/iTunes-/QuickTime-Tags
haben Vorrang. Leere, reine Whitespace-, UUID- und eigene Platzhalter-Werte werden verworfen, weitere Tag-Kandidaten
werden ausprobiert. Titel/Künstler fallen auf den **Originalnamen** ohne Extension zurück:
`Kobosil - You Need The Drug.mp4` → Künstler `Kobosil`, Titel `You Need The Drug`.
Getrennt wird nur an der ersten sinnvollen exakten Folge ` - `; sonst bleibt der gesamte
Dateinamensstamm der Titel. Letzte Fallbacks: `Unbekannter Titel`, `Unbekannter Künstler`,
`Unbekanntes Album`. Der interne Speichername ist beim Neuimport nie eine Metadatenquelle.

AVFoundation liest die Dauer separat mit präzisem Timing. Fehler einzelner Tags, fehlendes Album
und fehlendes/ungültiges Cover verhindern keinen Import; unspielbare Dateien oder MP4s ohne
Audio werden abgelehnt. Das erste dekodierbare eingebettete Cover wird im vorhandenen
`Song.artworkData` mit SwiftData external storage gespeichert. Bibliothekszeile, Mini-Player
und Vollbild-Player verwenden weiterhin dasselbe `ArtworkView` und denselben Placeholder.
Es werden keine Cover aus dem Internet geladen oder aus Videoframes erfunden.

Beim ersten Start nach diesem Update werden Altimporte einmalig (`metadataVersion`) geprüft.
Offensichtlich ungültige UUID-Titel werden auch bei bereits gesetzter Metadatenversion geprüft.
Die optionalen/defaultbelegten Modellfelder nutzen SwiftDatas automatische leichte Migration.
Gute vorhandene Titel/Künstler/Alben bleiben erhalten; fehlende Werte und Cover werden aus
der gespeicherten Datei oder einem zuverlässig erhaltenen Originalnamen ergänzt.
Alte UUID-Speichernamen werden **nicht** als Originalnamen interpretiert. Fehlen sowohl
Originalname als auch brauchbare Titel-Tags, ist der Originaltitel nicht rekonstruierbar:
der Eintrag zeigt `Unbekannter Titel`, behält Audiodatei, ID und Dauer und wird protokolliert.
Diese betroffenen alten Titel müssen gelöscht und aus der ursprünglichen Datei neu importiert
werden. In der Bibliothek kann der betreffende Eintrag jetzt nach links gewischt und gelöscht
werden. Erst nach erfolgreich gespeicherter Bibliotheksänderung wird die private Audiodatei
entfernt; die Originaldatei wird nicht gelöscht. Eine Neuinstallation würde
die gesamte lokale Bibliothek löschen und ist für diesen Fix nicht erforderlich.

Der ursprüngliche Fehler entstand durch den Titel-Fallback auf den bereits UUID-umbenannten
Dateinamen. Der spätere Quelldateinamen-Fallback war noch nicht persistent, prüfte Tags nicht
auf Brauchbarkeit und ließ Tag-Fehler den Import abbrechen.

Die Unit-Tests prüfen Parsing, Feldpriorität, UUIDs, Whitespace, alternative Tag-Kandidaten,
Artwork und die Reparatur. Der bestehende Actions-Workflow baut/testet den Simulator und
erzeugt danach `LocalMusic-unsigned.ipa` im Artifact `LocalMusic-unsigned-ipa`.
Die asynchronen AVFoundation-Aufrufe folgen der [Apple-Dokumentation zur Metadatenextraktion](https://developer.apple.com/documentation/avfoundation/retrieving-media-metadata).

## Korrekturen in 0.2.0 (2)

Im tatsächlich erzeugten vorherigen IPA fehlte `UIBackgroundModes`, obwohl das Projekt
`INFOPLIST_KEY_UIBackgroundModes = audio` enthielt. Eine explizite `Info.plist` liefert nun
das benötigte Array `[audio]`. Tests lesen die gebaute App-Konfiguration; der Workflow prüft
zusätzlich genau diese Eigenschaft im fertigen IPA, bevor es hochgeladen wird.
Die Audio-Session bleibt `.playback`; bei Wiederaufnahme wird sie erneut aktiviert.
Auch MP4 mit Videoanteil darf über `AVPlayer.audiovisualBackgroundPlaybackPolicy =
.continuesIfPossible` im Hintergrund weiterspielen. Erzwungenes Beenden der App beendet
weiterhin die Wiedergabe. Sperrbildschirm-Steuerung/Now Playing ist nicht Teil dieses Fixes.

Der Mini-Player sitzt mit `safeAreaInset` in jedem Tab-Inhalt oberhalb der nativen Tab-Leiste,
nicht mehr unter einem zusammengesetzten `VStack` mit `TabView`. Ein gehosteter UI-Test
prüft die tatsächlichen Bildschirmpositionen, Trefferflächen und Tab-Wechsel bei ausgewähltem
Song. Die Version steht sichtbar links oben in der Bibliothek, um alte installierte Builds
von diesem Update unterscheiden zu können. Die Screenshots allein belegen die installierte
Version nicht; sie zeigen aber die alte UUID-Darstellung.

Nach Installation bitte auf dem echten iPhone prüfen:

1. In der Bibliothek steht `0.2.0 (2)`.
2. `Kobosil - You Need The Drug.mp4` ohne Tags importieren: Künstler/Titel sind korrekt.
3. Einen Song starten, dann Home, Suche und Bibliothek wechseln; Mini-Player bleibt oberhalb der Tabs.
4. App verlassen und Bildschirm sperren: Audio läuft weiter; anschließend Pause/Play prüfen.
5. Alte nicht rekonstruierbare Einträge gezielt löschen und die Originaldateien erneut importieren.

Simulator-/Build-Prüfungen ersetzen keinen physischen iPhone-Test von Hintergrund-Audio.

## Phase 2

Als Nächstes bieten sich Lockscreen-Steuerung, Queue, Shuffle/Repeat, Playlists und Bearbeiten der Bibliothek an.
