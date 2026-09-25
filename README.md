# LocalMusic

Eine lokale iOS-Musikbibliothek für eigene Dateien. V1 nutzt SwiftUI, SwiftData und AVFoundation und benötigt weder Account noch Cloud noch Backend.

## Aktueller Funktionsumfang

- iOS 17+ mit Home, Suche und Bibliothek
- Auswahl von Audiodateien und kompatiblen MP4-Dateien über die Dateien-App
- Import nach `Application Support/ImportedAudio` in den privaten, persistenten App-Speicher
- Metadaten (Titel, Künstler, Album, Dauer und Artwork), wenn in der Datei vorhanden; verständliche Fallbacks sonst
- SwiftData-basierte lokale Bibliothek
- Song antippen: Wiedergabe starten; Mini-Player mit Play/Pause
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

## Phase 2

Als Nächstes bieten sich Vollbild-Player, Hintergrund-/Lockscreen-Audio, Queue, Shuffle/Repeat, Playlists sowie Löschen und Bearbeiten der Bibliothek an.
