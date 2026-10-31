# Kobra S1: direkte Dateiübertragung im lokalen WLAN

Die Schichtvorschau öffnet „An Drucker senden“. Der Nutzer gibt die IPv4-Adresse
des Druckers ein, prüft die Verbindung und bestätigt den Dateiversand. Gespeichert
wird ausschließlich die IP. Die Datei bleibt unverändert; es wird keine 3MF-Datei
durch Umbenennen vorgetäuscht. Ein neuer Dateiname vermeidet stilles Überschreiben.

Der Client fragt `GET http://IP:18910/info` ab, erwartet Modell-ID `20025` und
eine Upload-URL `fileUploadurl` direkt oder unter `urls`, gegebenenfalls innerhalb
von `data`. Er verwendet die frisch gelesene Sitzungs-URL für Multipart-POST mit
`filename`, `gcode` und `X-File-Length`. Dateien werden gestreamt, nicht vollständig
im Speicher gehalten. HTTP-Weiterleitungen, fremde Ziele und unerwartete
Antworten werden abgewiesen. Sitzungs-URLs und deren Tokens werden weder
gespeichert noch in Fehlermeldungen ausgegeben. Android erlaubt HTTP, weil das
Stock-LAN-Protokoll es benötigt; dieser Client beschränkt Ziele auf private,
literale IPv4-Adressen und Port 18910.

Es gibt keine MQTT-, `/ctrl`-, Druckstart-, Heiz- oder Bewegungsoperationen.
Die Übertragung wird nur bei explizitem Erfolgscode bestätigt. Diese Bestätigung
beweist weder die Druckbarkeit noch die Sichtbarkeit in der Drucker-Dateiliste.
Abbruch/Netzwerkfehler kann eine Teil- oder bereits angenommene Datei hinterlassen;
vor erneutem Senden muss die Liste am Drucker geprüft werden.

## Noch am echten Gerät zu prüfen

Zielgerät: Kobra S1 V2.7.2.7, ACE Pro V1.3.863 laut Nutzer.
Die Stock-Firmware kann eine Upload-URL erst nach einer weiteren LAN-Sitzung
bereitstellen oder App-G-Code zugunsten eines nativen Slicer-Pakets ablehnen.
In beiden Fällen meldet die App die Grenze, statt eine Übertragung zu simulieren.
Die Anleitung und der erste Testbuild ersetzen deshalb keine Hardwarefreigabe.
Ein Kobra-X-/Kobra-3-Protokollmitschnitt ist kein S1-Hardwaretest.

1. Handy und Drucker im selben WLAN; LAN-Modus am Drucker aktivieren.
2. IP eingeben und Verbindung prüfen. Noch keine Datei wird gesendet.
3. Kleines, zuvor in der App geslictes Modell senden, ohne Druckstart.
4. Erfolg/Ablehnung und Dateiliste am Drucker prüfen. Bei fehlender Upload-URL
   oder Ablehnung muss die Sitzungs-/Formatanbindung weiter angepasst werden.

Protokollfakten, keine übernommene Implementierung:
- https://github.com/ChestnutLabs/printer-protocol-orchard/blob/main/protocols/anycubic.md
- https://github.com/cluzl/kobra-bridge/blob/main/kobrax_client.py
- https://github.com/cuihuir/anycubic_bridge/blob/main/src/anycubic_bridge/app.py

Automatische Tests verwenden ausschließlich lokale simulierte HTTP-Drucker und
prüfen Multipart-Dateidaten, Sitzungserneuerung, Modellprüfung, Fehlerantworten,
fremde Upload-Ziele und die ausdrückliche Versandbestätigung in der Oberfläche.
