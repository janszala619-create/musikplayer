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
Nur die private Speicherdatei und Song-ID bleiben UUID-basiert. Der externe URL-Zugriff wird
mit `startAccessingSecurityScopedResource()`/`defer` begrenzt; für Wiedergabe wird ausschließlich
die persistente Kopie verwendet.

Jedes Feld wird unabhängig aufgelöst: brauchbare eingebettete Common-/ID3-/iTunes-/QuickTime-Tags
haben Vorrang. Leere, reine Whitespace- und UUID-Werte werden verworfen, weitere Tag-Kandidaten
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
Die optionalen/defaultbelegten Modellfelder nutzen SwiftDatas automatische leichte Migration.
Gute vorhandene Titel/Künstler/Alben bleiben erhalten; fehlende Werte und Cover werden aus
der gespeicherten Datei oder einem zuverlässig erhaltenen Originalnamen ergänzt.
Alte UUID-Speichernamen werden **nicht** als Originalnamen interpretiert. Fehlen sowohl
Originalname als auch brauchbare Titel-Tags, ist der Originaltitel nicht rekonstruierbar:
der Eintrag zeigt `Unbekannter Titel`, behält Audiodatei, ID und Dauer und wird protokolliert.
Diese betroffenen alten Titel müssen gelöscht und aus der ursprünglichen Datei neu importiert
werden. V1 hat noch keine Löschfunktion; bis diese vorhanden ist, kann die Originaldatei neu
importiert werden, der alte Platzhalter-Eintrag bleibt bestehen. Eine Neuinstallation würde
die gesamte lokale Bibliothek löschen und ist für diesen Fix nicht erforderlich.

Der ursprüngliche Fehler entstand durch den Titel-Fallback auf den bereits UUID-umbenannten
Dateinamen. Der spätere Quelldateinamen-Fallback war noch nicht persistent, prüfte Tags nicht
auf Brauchbarkeit und ließ Tag-Fehler den Import abbrechen.

Die Unit-Tests prüfen Parsing, Feldpriorität, UUIDs, Whitespace, alternative Tag-Kandidaten,
Artwork und die Reparatur. Der bestehende Actions-Workflow baut/testet den Simulator und
erzeugt danach `LocalMusic-unsigned.ipa` im Artifact `LocalMusic-unsigned-ipa`.
Die asynchronen AVFoundation-Aufrufe folgen der [Apple-Dokumentation zur Metadatenextraktion](https://developer.apple.com/documentation/avfoundation/retrieving-media-metadata).

## Phase 2

Als Nächstes bieten sich Vollbild-Player, Hintergrund-/Lockscreen-Audio, Queue, Shuffle/Repeat, Playlists sowie Löschen und Bearbeiten der Bibliothek an.
