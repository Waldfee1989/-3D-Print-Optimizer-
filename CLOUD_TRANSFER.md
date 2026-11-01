# Anycubic International: Cloud-Versand aus der Schichtvorschau

Die Standardroute „An Drucker senden“ verwendet jetzt die Cloud. Die bisherige
lokale LAN-Route bleibt als ausdrückliche Alternative verfügbar. Cloudbetrieb
benötigt Internet und einen beim eigenen Anycubic-Konto gebundenen Drucker mit
ausgeschaltetem LAN-Modus. Es wird kein eigener Server und kein Bezahlservice
eingerichtet.

## Anmeldung

Die App öffnet die offizielle Anycubic-Webseite in der System-WebView. Passwort,
Captcha und 2FA werden dort vom Nutzer bedient. Erst nach „Konto verbinden“ liest
die App genau den `XX-Token`-Sitzungswert vom Ursprung
`https://cloud-universe.anycubic.com`. Der Ursprung wird sowohl in Dart als auch
innerhalb des JavaScript-Ausdrucks geprüft. Andere Speicher, Formulare,
Passwortfelder und Cookies werden nicht ausgelesen. Die Anmeldung darf ausschließlich
über HTTPS auf den vorgesehenen Anycubic-/MakerOnline-/Login-Ursprüngen navigieren.
Zertifikatsfehler werden nicht umgangen. Manche Identitätsanbieter können die
Anmeldung in eingebetteten Browsern ablehnen; dies muss im Live-Test geprüft werden.

Der native Client hält den Token nur im Arbeitsspeicher. Er schreibt ihn nicht in
SharedPreferences, URLs, Repository oder Diagnosen. Die offizielle Webseite
verwaltet ihre Web-Sitzung selbst. „Konto trennen“ verwirft die native Sitzung und
löscht Cookies und Web-Speicher des eingebetteten Browsers. Es gibt keinen
eigenen Cloud-OAuth-Client und keine Behauptung einer offiziellen Drittanbieter-API.

## Upload und Auftrag

Der Client liest die kontogebundene Druckerliste, bietet nur Kobra S1 / S1 Combo an
und benötigt eine ausdrückliche Auswahl. Nach Upload-Bestätigung reserviert er
Speicher, streamt die unveränderte `.gcode` per signierter PUT-Adresse in den
vom Cloudserver gemeldeten S3-Speicher, registriert die Datei und entsperrt die
Reservierung. Anycubic-Token und Signaturheader gehen ausschließlich an den
festen Anycubic-API-Ursprung, niemals an S3. Weiterleitungen und fremde Ziele werden
nicht verfolgt. Reservierungsbereinigung löscht nur sicher noch nicht registrierte
Daten; ein unklarer Claim wird nicht durch automatisches Löschen behandelt.

Ein Upload ist keine Drucker-Dateiannahme und startet keinen Druck. Ein weiterer,
separat bestätigter Auftrag liest den aktuellen Druckerstatus neu und verweigert
offline/beschäftigte/unbekannte Zustände. Unterstützt wird zunächst ein Material
mit einem ACE Pro (vier Plätze) oder eine ausdrücklich bestätigte externe Rolle
bei als abwesend gemeldetem ACE. ACE-Index, Farbe und Material kommen aus frischen
Cloud-Daten; leere oder unpassende Plätze werden nicht angenommen. Unbekannte
Materialverbrauchsgramm werden im optionalen Zuordnungsfeld mit 0 angegeben und
nicht als gemessener Verbrauch ausgegeben. Mehrfarbdruck und mehrere ACEs sind
nicht umgesetzt.

Der Druckauftrag nutzt den bekannten REST-Auftrag `order_id=1`. Die Cloud muss
eine Nachrichten-ID bestätigen. Dies bedeutet nur, dass die Cloud den Auftrag
angenommen hat; es bestätigt weder Druckerdownload noch tatsächlichen Druckbeginn.
Kein Auftrag wird automatisch wiederholt, auch nicht nach einer unklaren Antwort.
Entwicklungsprüfungen verwenden ausschließlich synthetische lokale HTTP-Server;
es werden keine echten Konten oder physischen Drucker angesteuert.

## Quellen der Protokollfakten

Eigenständige Dart-Implementierung nach den öffentlich dokumentierten Nachrichten-
und Feldformaten von `anycubic-cloud-api` 0.4.36, insbesondere `models/auth.py`,
`models/cloud_upload.py`, `api/functions.py`, `data_models/orders.py` und
`data_models/printer_properties.py`. Die App-Identifikatoren und der konstante
Web-Signaturschlüssel sind öffentliche Web-Client-Protokollparameter dieser
Bibliothek, keine Nutzerzugangsdaten. Es wurden keine TLS-Privatschlüssel oder
MQTT-Zertifikate übernommen.

- https://github.com/Nino6689/hass-anycubic
- https://pypi.org/project/anycubic-cloud-api/0.4.36/
- https://pub.dev/packages/webview_flutter

## Offene Live-Prüfungen

Ohne Sitzung des Nutzers sind Anmeldung, Cloud-Berechtigungen, S3-Zielformat,
Dateiverarbeitung des App-G-Codes und Annahme auf Kobra S1 V2.7.2.7 mit ACE Pro
V1.3.863 nicht am Gerät geprüft. Die Oberfläche kennzeichnet dies als Testversion.
Die nicht offiziell dokumentierte API kann sich ändern oder Web-Sitzungen für
einzelne Operationen ablehnen. Vor einer Funktionsfreigabe müssen diese Schritte
mit dem eigenen Konto geprüft werden; Simulationen sind kein Live-Nachweis.

## REST-Antwortkorrektur (1. November 2026)
Die aktuell öffentlich ausgelieferte offizielle Web-App
`https://cloud-universe.anycubic.com/js/app.982cbff9.js` prüft REST-Erfolg
mit `code === 1` und behandelt `10001` als abgelaufene Anmeldung.
Der bisherige Client hatte REST- und Druckernachrichten-Codes verwechselt.
Er akzeptiert jetzt gezielt 1 sowie die kompatiblen 0/200; unbekannte Codes
und fehlende Daten bleiben Fehler. Servermeldungen werden nicht angezeigt,
nur der begrenzte numerische Code und der fehlgeschlagene Schritt.
Eine fehlgeschlagene Druckerabfrage gilt nicht mehr als leeres Konto.
Die Regressionstests laufen standardmäßig mit REST-Code 1; Upload,
Druckfreigabe und Wiederholschutz bleiben darin separat geprüft.
Dies ist noch kein Test mit einem echten Konto oder Drucker.
