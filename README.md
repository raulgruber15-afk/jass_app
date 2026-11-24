# Jass (Flutter)

Offline-Jass für Android und iPhone. Stand: Etappe 1, **Schieber gegen drei Computergegner**.

## Aufbau

```
lib/
  engine/          Spielregeln, ohne Bildschirm-Code (testbar, später fürs WLAN-Spiel)
    cards.dart       Karten, Farben, Werte
    game_mode.dart   Trumpf/Obenabe/Undenufe: Punkte und wer sticht
    rules.dart       erlaubte Karten, Weis, Stöck
    schieber.dart    ganzer Spielablauf mit Punktezählung
    bot.dart         Computergegner (Anfänger, Stammtisch)
  ui/              Bildschirme
  main.dart        Startbildschirm mit Einstellungen
assets/cards/      Kartenbilder (aus karten/png@2x)
assets/icon/       App-Symbol
test/              automatische Regel-Tests
docs/              Store-Anleitung, Datenschutz, Store-Texte
tools/             Hilfsskripte (Android-Schlüssel)
codemagic.yaml     Cloud-Builds für iPhone und Android
.github/workflows  Automatischer Test-Build (Android-APK)
```

## Befehle

```
flutter pub get        # Pakete laden
flutter test           # Regel-Tests
flutter run            # auf angeschlossenem Handy/Emulator starten
flutter run -d chrome  # im Browser ausprobieren
flutter build apk      # Android-Test-App
flutter build appbundle  # für den Play Store (braucht android/key.properties)
dart run flutter_launcher_icons  # App-Symbole neu erzeugen
```

## Regeln und Annahmen (einstellbar oder leicht änderbar)

- Schieber, gespielt im Gegenuhrzeigersinn; die Person mit Karo 7 bestimmt in der ersten Runde Trumpf, danach reihum.
- Einmal schieben zum Partner; wer Trumpf bestimmen musste, spielt aus.
- Puur muss nie angegeben werden; Untertrumpfen verboten ausser nur noch Trumpf in der Hand.
- Weis wird automatisch gewiesen und nach dem ersten Stich gezählt; nur das Team mit dem höchsten Weis zählt.
- Stöck 20 Punkte, wird beim Ausspielen der zweiten Karte gezählt.
- Multiplikatoren (Annahme): Herz/Karo ×1, Pik/Kreuz ×2, Obenabe/Undenufe ×3. Abschaltbar.
- Spielende («Bedanken»): Stöck und Weis zählen sofort; erreichen beide Teams das Ziel erst mit den Stichpunkten, gewinnt das Team mit mehr Punkten.

## Store

Siehe [docs/STORE_ANLEITUNG.md](docs/STORE_ANLEITUNG.md). Bundle-ID (fest, nie mehr ändern): `ch.gruber.jass`.
