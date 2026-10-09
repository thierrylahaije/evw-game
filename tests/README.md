# Eindcontrole

Voor de mobiele bediening controleert `test_mobile_controls.gd` gelijktijdig sturen en gas geven, het loslaten van één vinger, het vrijgeven van pedalen, het pauzeren bij kalibratie en staande schermstand, en de snelheidswaarde:

```sh
godot --headless --path . --script res://tests/test_mobile_controls.gd
node --test tests/test_mobile_browser.mjs
```

De Node-test controleert de browserkant: verdwenen aanrakingen, sensortoestemming,
sensoruitval en het ontbreken van sensorgegevens.

`test_final_routes.gd` doorloopt voor elk van de drie routes de echte missie-
en docklogica: ophalen, twee afleverpunten, terugdock, botsingtellingen en
lokale scoreopslag. De test plaatst de combinatie gecontroleerd op de doelen;
dit is een geautomatiseerde functionele doorloop, geen handmatig gereden rit.

```sh
EVW_SCORE_API_URL=disabled godot --headless --path . --script res://tests/test_final_routes.gd
```

De wegtrajecten die de GPS berekent zijn ongeveer 2013 m, 1984 m en 2009 m.
Het verschil tussen de kortste en langste route is 1,5%. Elke route heeft twee
afleverpunten.

Voor de online test: start eerst de lokale API met een testdatabase en voer
dan de Godot-test uit:

```sh
EVW_LOCAL_DB_PATH=/tmp/evw-test.db EVW_API_PORT=18787 python3 server/score_api.py
EVW_SCORE_API_URL=disabled EVW_TEST_API_URL=http://127.0.0.1:18787 godot --headless --path . --script res://tests/test_online_scores.gd
```

De scorestraffen staan nog op 400 punten per gebouw/muur, 700 per auto en
500 per rood licht. Ze zijn in de tests consistent tussen game en server.
Voor de laatste afstelling zijn nog drie handmatig gereden volledige ritten
nodig, inclusief verkeerslichten en echte manoeuvreertijd bij de docks.

Voor de gedeelde JSON-opslag zonder server:

```sh
EVW_SCORE_API_URL=disabled EVW_TEST_TMP_DIR=/tmp godot --headless --path . --script res://tests/test_shared_scores.gd
```

Deze test controleert lokale wachtrij, één bestand per rit, ranglijst per
chauffeur en dat opnieuw synchroniseren geen dubbele ritten maakt.
