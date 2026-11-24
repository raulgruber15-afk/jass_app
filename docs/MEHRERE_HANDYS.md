# Jassen mit mehreren Handys (WLAN oder Hotspot)

Jede Person spielt auf dem eigenen Handy und sieht nur die eigenen Karten.
Internet braucht es nicht. iPhone und Android können gemischt mitspielen.

## So geht's

1. **Gleiches Netz:** Alle Handys sind im gleichen WLAN.
   Ohne WLAN (z. B. im Zug, im Restaurant): Ein Handy schaltet den
   **persönlichen Hotspot** ein, die anderen verbinden sich damit.
   Am besten eröffnet das Hotspot-Handy auch das Spiel.
2. **Gastgeber:** Startseite → «Mit Freunden» → «Jeder sein Handy» →
   Namen eingeben → **«Spiel eröffnen»**. Es erscheint ein QR-Code.
3. **Mitspieler:** Startseite → «Mit Freunden» → «Jeder sein Handy» →
   Namen eingeben → **«Beitreten»** → QR-Code scannen.
   Ohne Kamera: die Adresse unter dem QR-Code eintippen.
4. Der erste Mitspieler wird **Partner** des Gastgebers (gegenüber),
   die nächsten sind die Gegner. Freie Plätze spielt der Computer.
5. Gastgeber tippt **«Spiel starten»**.

## Gut zu wissen

- Das Spiel läuft auf dem Handy des Gastgebers. Dieses Handy bitte nicht
  sperren oder die App wechseln, sonst stockt das Spiel für alle.
- Fällt ein Mitspieler raus (Akku, Funkloch), spielt der Computer für ihn
  weiter. Mit «Beitreten» und **gleichem Namen** kommt er an seinen Platz
  zurück.
- Nur der Gastgeber startet die nächste Runde und eine neue Partie.
- **iPhone:** Beim ersten Mal fragt das iPhone, ob die App «Geräte im
  lokalen Netzwerk finden» darf. Bitte **erlauben**, sonst klappt die
  Verbindung nicht. Nachträglich: Einstellungen → Datenschutz →
  Lokales Netzwerk → Jass.
- Manche Gäste-WLANs (Hotel, Firma) lassen Handys nicht miteinander reden.
  Dann den Hotspot eines Handys verwenden.

## Technik (für später)

- TCP-Verbindung im lokalen Netz, Port 47474, Nachrichten als JSON-Zeilen.
- Der QR-Code enthält `jass1|<IP-Adressen>|<Port>`.
- Code: `lib/net/net_game.dart` (Gastgeber `JassHost`, Mitspieler
  `JassGuest`), Bildschirme in `lib/ui/net_screens.dart`.
