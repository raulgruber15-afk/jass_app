# Jass in den App Store und Play Store bringen

Diese Anleitung erklärt, was **du selbst** erledigen musst, damit die App in den Stores erscheint. Den Code und die technische Vorbereitung übernimmt Claude. Du brauchst **keinen Mac**: Die iPhone-Version wird in der Cloud gebaut (Codemagic).

Zeitbedarf grob: 2 bis 3 Abende für Konten und Einrichtung, dazu Wartezeiten (Kontoprüfung 1 bis 3 Tage, Apple-Prüfung 1 bis 2 Tage, Google-Testphase 14 Tage).

---

## Übersicht: Was kostet was?

| Was | Kosten | Wofür |
|---|---|---|
| Apple Developer Program | 99 USD pro Jahr | Pflicht für den App Store |
| Google Play Console | 25 USD einmalig | Pflicht für den Play Store |
| Codemagic | gratis im Grundkontingent (rund 500 Build-Minuten pro Monat, Stand prüfen auf codemagic.io) | baut die iPhone-App ohne Mac |
| GitHub | gratis | speichert den Code, baut Android-Test-Apps |

---

## Schritt 1: Zwei Entscheide, die man später nicht mehr ändern kann

1. **App-Kennung (Bundle-ID): `ch.gruber.jass`** ✓ festgelegt. Diese Kennung ist für immer an die App gebunden und überall im Projekt eingetragen. Verwende genau diese bei Apple (Schritt 4.3) und Google.
2. **App-Name im Store.** «Jass» ist sehr wahrscheinlich schon vergeben. Vorschläge: «Jass offline – Schieber», «Stammtisch-Jass», «Jass am Tisch». Auf dem Handy-Bildschirm steht trotzdem kurz «Jass».

## Schritt 2: Code auf GitHub (empfohlen)

Damit Codemagic und GitHub die App bauen können, muss der Code in einem GitHub-Repository liegen.

1. Auf <https://github.com> anmelden (Konto `raulgruber15-afk` besteht schon).
2. Oben rechts **+ → New repository**, Name z. B. `jass_app`, **Private** wählen, ohne README erstellen.
3. Claude Bescheid geben. Claude verknüpft das Repository mit dem Projekt und lädt den Code hoch.

Danach baut GitHub bei jeder Änderung automatisch eine **Android-Test-App** (APK). Du findest sie unter *Actions → neuester Lauf → Artifacts → jass-android-apk*. Die APK kannst du direkt aufs Android-Handy laden und installieren (Installation aus «unbekannten Quellen» erlauben).

## Schritt 3: Google Play (Android)

1. **Konto eröffnen:** <https://play.google.com/console/signup> → «Für mich selbst» (Privatperson) → 25 USD bezahlen → Ausweis-Prüfung abschliessen (dauert 1 bis 3 Tage).
2. **Upload-Schlüssel erstellen** (einmalig, sehr wichtig):
   - Claude kann das für dich erledigen, oder du führst auf einem Computer mit Java `tools/android-schluessel-erstellen.sh` aus.
   - Ergebnis: eine Datei `jass-upload-keystore.jks` plus Passwort. **Beides gut sichern** (z. B. Passwort-Manager und USB-Stick). Ohne diesen Schlüssel kannst du keine Updates mehr hochladen. Google bietet zwar eine Wiederherstellung an, aber das dauert.
   - Die Datei und das Passwort **nie** ins GitHub-Repository oder in einen Chat stellen. Du lädst sie nur bei Codemagic hoch (Schritt 5).
3. **App anlegen:** In der Play Console «App erstellen» → Name, Sprache Deutsch (Schweiz), «Spiel», «Kostenlos».
4. **Pflichtangaben ausfüllen** (Menü «App-Inhalte»):
   - Datenschutzerklärung: Link auf eine öffentliche Seite mit dem Text aus `docs/DATENSCHUTZ.md` (siehe Schritt 6).
   - Datensicherheit: «Es werden keine Daten erhoben oder geteilt».
   - Altersfreigabe-Fragebogen: Kartenspiel, kein Glücksspiel um Geld, keine Werbung, keine Chats.
   - Zielgruppe: ab 13 Jahren (einfachste Wahl, kein Kinder-Programm nötig).
   - Werbung: «Nein».
5. **Store-Eintrag:** Kurz- und Langbeschreibung (Vorschlag in `docs/STORE_TEXTE.md`), App-Symbol 512 × 512 (`assets/icon/app_icon.png` verkleinern, macht Claude), Vorschaubild 1024 × 500, mindestens 2 Bildschirmfotos.
6. **Testphase (Pflicht für neue Privatkonten):** Google verlangt einen **geschlossenen Test mit mindestens 12 Testpersonen während 14 Tagen**, bevor die App öffentlich werden darf. Freunde und Familie mit Android-Handy reichen; sie brauchen nur ein Google-Konto und müssen die App installiert lassen.
7. Nach den 14 Tagen: «Produktion» beantragen → Google prüft (meist wenige Tage) → App ist im Play Store.

## Schritt 4: Apple App Store (iPhone)

1. **Apple-ID mit Zwei-Faktor-Schutz** (hast du vermutlich schon).
2. **Developer Program beitreten:** <https://developer.apple.com/programs/enroll/> → als **Einzelperson** (Individual) → 99 USD pro Jahr. Am einfachsten über die App «Apple Developer» auf einem iPhone. Freischaltung dauert meist 1 bis 2 Tage.
3. **App-ID registrieren:** <https://developer.apple.com/account/resources/identifiers> → «+» → App IDs → App → Bundle-ID `ch.gruber.jass`.
4. **App in App Store Connect anlegen:** <https://appstoreconnect.apple.com> → Apps → «+» → Neue App → Plattform iOS, Name, Sprache Deutsch, Bundle-ID aus der Liste, SKU z. B. `jass-001`.
   - Danach unter *App-Informationen* die **Apple ID** (eine Zahl) notieren und Claude geben. Sie kommt in `codemagic.yaml`.
5. **API-Schlüssel für Codemagic:** App Store Connect → Benutzer und Zugriff → Integrationen → App Store Connect API → «+» → Name «Codemagic», Zugriff **App Manager** → Schlüssel (.p8-Datei) herunterladen. **Die Datei kann man nur einmal herunterladen!** Ausserdem «Issuer ID» und «Key ID» notieren.
6. **Pflichtangaben:**
   - Datenschutz-URL (Schritt 6).
   - App-Datenschutz: «Keine Daten erfasst».
   - Altersfreigabe: alles «Nein» bzw. «Keine». Bei «Simuliertes Glücksspiel» ehrlich antworten: Jass ohne Geldeinsatz gilt in der Regel nicht als simuliertes Glücksspiel; im Zweifel «Selten/schwach» wählen (Freigabe dann 12+ statt 4+).
   - Bildschirmfotos für 6,9-Zoll-iPhone (1320 × 2868). Claude kann sie erzeugen.
   - Die App ist nur für iPhone eingestellt, darum braucht es **keine** iPad-Bildschirmfotos.
7. Der Build kommt von Codemagic (Schritt 5) automatisch in **TestFlight**. Dort kannst du ihn selbst auf dem iPhone testen (App «TestFlight» installieren).
8. Wenn alles passt: in App Store Connect den Build auswählen → «Zur Prüfung einreichen». Apple prüft meist innert 1 bis 2 Tagen.

## Schritt 5: Codemagic einrichten (baut ohne Mac)

1. <https://codemagic.io> → mit GitHub anmelden → Repository `jass_app` hinzufügen. Codemagic erkennt die Datei `codemagic.yaml` automatisch.
2. **Teams → Integrations → App Store Connect:** API-Schlüssel aus Schritt 4.5 eintragen (Issuer ID, Key ID, .p8-Datei), Name genau `JassAppStore`.
3. **Code signing identities:**
   - *iOS certificates:* «Generate certificate» (Codemagic erstellt das Apple-Zertifikat für dich).
   - *Android keystores:* Upload-Schlüssel aus Schritt 3.2 hochladen, Referenzname `jass_upload`.
4. Für den automatischen Upload in den Play Store (optional, sonst lädst du die .aab-Datei selbst in der Play Console hoch): ein Google-Cloud-Dienstkonto anlegen und als Variable `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` in der Gruppe `google_play` speichern. Anleitung: <https://docs.codemagic.io/yaml-publishing/google-play/>. Achtung: Den **allerersten** Upload muss man bei Google immer von Hand in der Play Console machen.
5. Build starten: Workflow **«iOS – App Store (TestFlight)»** oder **«Android – Play Store»**.

## Schritt 6: Datenschutzerklärung online stellen

Beide Stores verlangen einen öffentlichen Link. Der Text steht in `docs/DATENSCHUTZ.md` (die App sammelt keine Daten). Einfachste Wege:
- **GitHub Pages:** Ein zweites, öffentliches Repository `jass-datenschutz` mit dieser Datei, unter *Settings → Pages* einschalten. Claude kann das vorbereiten.
- Oder eine kostenlose Seite bei Google Sites.

Bitte Namen und E-Mail-Adresse im Text ergänzen (Platzhalter sind markiert).

## Schritt 7: Kartengrafiken und Rechte

Vor dem Hochladen muss geklärt sein, dass du das Vintage-Kartenset in einer veröffentlichten App verwenden darfst (siehe offene Frage im Projektplan). Ohne Nutzungsrecht kann Apple oder Google die App entfernen. Die Grafiken sind im Code austauschbar (`assets/cards/`).

---

## Kurz-Checkliste

- [x] Bundle-ID festgelegt: `ch.gruber.jass`
- [ ] Store-Name festgelegt
- [x] GitHub-Repository angelegt und mit dem Projekt verknüpft
- [ ] Google-Play-Konto (25 USD) eröffnet und verifiziert
- [ ] Android-Upload-Schlüssel erstellt und doppelt gesichert
- [ ] 12 Android-Testpersonen gefunden
- [ ] Apple Developer Program (99 USD/Jahr) beigetreten
- [ ] App in App Store Connect angelegt, Apple ID an Claude
- [ ] App-Store-Connect-API-Schlüssel (.p8) erstellt
- [ ] Codemagic verbunden, Schlüssel hinterlegt
- [ ] Datenschutzerklärung online
- [ ] Rechte an den Kartengrafiken geklärt
