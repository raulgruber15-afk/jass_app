#!/usr/bin/env bash
# Erstellt den Upload-Schlüssel für den Google Play Store.
# Braucht Java (keytool). Einmal ausführen, Datei und Passwort GUT SICHERN.
set -euo pipefail
OUT="${1:-$HOME/jass-upload-keystore.jks}"
if [ -e "$OUT" ]; then
  echo "Datei $OUT gibt es schon. Abbruch, damit nichts überschrieben wird."; exit 1
fi
keytool -genkeypair -v \
  -keystore "$OUT" \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
echo
echo "Fertig: $OUT"
echo "Jetzt android/key.properties.example nach android/key.properties kopieren und ausfüllen,"
echo "oder die Datei bei Codemagic unter 'Code signing identities > Android keystores' hochladen."
