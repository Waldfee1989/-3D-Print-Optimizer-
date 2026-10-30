# Foto-Bauteile: privater Erkennungsdienst

Die Android-App wählt 4–8 Ansichten und verarbeitet Rückfragen mit Messmarkierungen direkt auf den Fotos. Dieser Dienst nutzt OpenAI Responses mit Bild-Eingaben und strukturierten Antworten. Aus bestätigten mm-Maßen und ausdrücklich freigegebenen Näherungen erzeugt ein begrenzter CSG-Generator echte binäre STL-Dateien mit geschlossenen Volumen. Das ist eine parametrisierte Nachkonstruktion unterstützter technischer Formen, keine allgemeine Photogrammetrie und keine Garantie für maßhaltige oder funktionsfähige Passungen.

## Betrieb

`pip install -r requirements.txt`, dann `python -m photo_parts.app` aus diesem Verzeichnis. Alternativ das Dockerfile verwenden. Vor einem produktiven Start setzen:

- `OPENAI_API_KEY`: nur auf dem Server, niemals in App, Repository oder Chat eintragen.
- `PHOTO_PART_MODEL`: ein für den Betreiber freigegebenes OpenAI-Modell mit Bild-Eingaben und Structured Outputs. Absichtlich kein automatischer Modellwechsel.
- `PHOTO_PART_ACCESS_TOKEN`: eigener zufälliger Zugangscode mit mindestens 32 Zeichen; die App verwendet ihn für diesen Dienst. Kein OpenAI-Schlüssel.
- `PHOTO_PART_HOURLY_LIMIT`: optional, Standard 30 Analysen pro Stunde für diesen privaten Einzelnutzerdienst.
- `BIND`/`PORT`: standardmäßig `127.0.0.1:8080`. Container hinter einem HTTPS-Proxy betreiben. Die Android-App akzeptiert ausschließlich HTTPS ohne Weiterleitungen.

Der Dienst ist nicht veröffentlicht oder mit Zugangsdaten versehen. Er benötigt separat eingerichtetes Hosting und API-Abrechnung. Die ChatGPT-Anmeldung konfiguriert diesen Dienst nicht. Ohne Einrichtung meldet er ausdrücklich „noch nicht eingerichtet“; es gibt keine simulierten Online-Ergebnisse. Der Dienst protokolliert keine Bilder oder Eingaben und sendet Responses mit `store:false`; das ersetzt keine Erklärung der Datenverarbeitung durch den API-Anbieter.

## Vertrag und Grenzen

`POST /v1/analyze`: `{images:[base64PNG,...], answers:{id:number|string}, previous:plan|null}`. `POST /v1/generate`: `{plan,answers,image_count,assumptions_accepted}`. Beide benötigen `Authorization: Bearer <Zugangscode>`. Bilder verlassen das Gerät erst nach ausdrücklich betätigtem Analyseknopf. EXIF wird serverseitig entfernt. Die App sendet bereits normalisierte PNG-Daten.

Ein Maß hat eine stabile ID, einen eindeutigen Umfang, eine Erklärung und entweder zwei normierte Endpunkte im zugehörigen Foto oder keine Markierung, wenn die Stelle nicht sichtbar ist. Bestehende Fragebedeutungen dürfen über mehrere Runden nicht geändert werden. Zahlenantworten kommen allein vom Nutzer. Bei fehlenden Angaben oder Widersprüchen wird keine STL generiert. Bei nicht unterstützten Formen muss die Analyse dies sagen.

Geometrie darf nur Boxen, Zylinder/Kegelstümpfe und Kugeln addieren oder abziehen, mit beschränkten Rechenausdrücken auf bestätigten Maß-IDs. Kein `eval`, generierter Code, Dateizugriff oder Shell. Geometrieberechnung läuft in einem Prozess mit Zeit- und Speichergrenze. Es wird eine echte STL erzeugt und auf geschlossene positive Volumen geprüft; die semantische Übereinstimmung mit dem Foto bleibt eine zu prüfende Modellschätzung.

## Validierung

`OPENBLAS_NUM_THREADS=1 python -m unittest discover -s tests -v`

Tests nutzen feste Analyseverträge und lokale Geometrie; sie ersetzen keinen Live-Test mit der eingerichteten Bilderkennung und keine Passprobe am realen Druck. Live-Bildanalyse ohne konfigurierte Zugangsdaten ist nicht geprüft.

Offizielle Anbindung: https://developers.openai.com/api/docs/guides/images-vision?api-mode=responses und https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses
