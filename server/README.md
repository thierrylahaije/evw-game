# EVW web-MVP: scoreopslag

De Godot-webgame is statisch en kan later op GitHub Pages staan. De score-API
staat in `server/worker/` en draait later als Cloudflare Worker. Alleen die
Worker kent `TURSO_DATABASE_URL` en `TURSO_AUTH_TOKEN`; de browser krijgt
uitsluitend de publieke Worker-URL. Er is nu niets gedeployd.

## Nu lokaal testen

De webexport wordt gemaakt met Godot 4.7.2 en de officiële webtemplate:

```sh
python3 tools/build_web.py --godot /pad/naar/Godot
python3 -m http.server 8765 --directory dist/web
```

Open `http://localhost:8765`. Zonder API-URL werkt het spel en bewaart het
scores lokaal in de browser. Browseropslag kan worden gewist als iemand
sitegegevens verwijdert. De desktopversies blijven hun bestaande lokale
opslag gebruiken.

De bestaande Python-API kan lokaal met SQLite worden getest:

```sh
EVW_LOCAL_DB_PATH=server/scores.db python3 server/score_api.py
python3 -m unittest discover -s server -v
cd server/worker && npm test
```

De webversie heeft voor de lokale Python-API browser-CORS nodig. Voor de
uiteindelijke MVP is de Worker bedoeld; de Python-server is een lokale
ontwikkel- en referentie-implementatie.

## Later deployen

1. Maak een Cloudflare-account. Maak in Turso de tabellen uit
   `server/worker/schema.sql` aan, via de Turso SQL-console of lokaal met
   `python3 server/worker/init_db.py` nadat de twee Turso-variabelen als
   omgevingsvariabelen zijn ingesteld.
2. Vul in `server/worker/wrangler.toml` de exacte GitHub Pages **origin** in
   bij `EVW_ALLOWED_ORIGIN`, bijvoorbeeld `https://naam.github.io`.
   Een projectpad hoort hier niet bij. Voor lokale browsertests kan ook
   `http://localhost:8765` als tweede origin worden toegevoegd.
3. Zet de twee Turso-waarden als Cloudflare Worker-**secrets** met Wrangler of
   via het Cloudflare-dashboard. Zet ze nooit in `wrangler.toml`, `project.godot`,
   `api-config.js` of GitHub Secrets voor de statische website.
4. Deploy `server/worker/` met Wrangler. Controleer daarna `/health` en de
   score-endpoints. Dit gebeurt pas in de deploymentfase.
5. Bouw de webgame met
   `python3 tools/build_web.py --api-url https://<worker>.workers.dev --godot /pad/naar/Godot`.
   Publiceer de **inhoud** van `dist/web/` op GitHub Pages. De build zet de
   Worker-URL in `api-config.js`, los van de Godot-`.pck`; die URL kan later
   ook rechtstreeks in dat bestand worden bijgewerkt.
6. Test de volledige keten: rit afronden, ronde in Turso, ranglijst op een
   tweede browser, en offline afgeronde rit na herstel opnieuw uploaden.

De score-API accepteert `POST /api/players`, `POST /api/rounds`,
`GET /api/leaderboard?limit=10`, `GET /api/players/<id>` en `GET /health`.
De server herberekent de score en verwerkt hetzelfde ronde-ID slechts eenmaal.
De game bewaart iedere uitslag eerst lokaal en probeert mislukte uploads later
opnieuw. Er is geen accountauthenticatie of cheatpreventie in deze MVP:
een speler kan met een aangepaste client fictieve ritgegevens indienen.
