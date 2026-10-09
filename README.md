# EVW Game

Een Godot 4.7.2-game met een webexport voor GitHub Pages en een online ranglijst. De game bewaart ritten lokaal en uploadt ze naar de score-API zodra die bereikbaar is.

## Projectonderdelen

- `assets/` en de Godot-bronbestanden: game en resources.
- `tools/build_web.py`: maakt de webexport in `dist/web/` en schrijft de publieke API-URL naar `api-config.js`.
- `.github/workflows/pages.yml`: bouwt met Godot 4.7.2 en publiceert `dist/web/` naar GitHub Pages.
- `server/worker/`: Cloudflare Worker en Turso-schema voor de score-API.
- `dist/`: gegenereerde uitvoer; deze map wordt niet in Git bijgehouden.

## Lokaal starten en bouwen

Open `project.godot` in Godot 4.7.2 om de game te starten.

Voor een webexport is Godot 4.7.2 met de Web-exporttemplates nodig:

```sh
python3 tools/build_web.py --godot /pad/naar/godot
python3 -m http.server 8765 --directory dist/web
```

Open daarna `http://localhost:8765`. Zonder API-URL werkt de game met lokale scores. Voor een lokale export die de online API gebruikt:

```sh
python3 tools/build_web.py --godot /pad/naar/godot --api-url https://<worker>.workers.dev
```

`--api-url` is een openbaar HTTPS-adres. Gebruik hier nooit Turso-inloggegevens.

Bij **Nieuwe game** kiest de speler eerst **Computer** of **Telefoon**. Op de telefoon zijn er stuurknoppen of kantelbesturing. De pedalen blijven in beide mobiele modi op het scherm. Voor kantelbesturing moet de speler de bewegingssensor vanuit het spel inschakelen en de comfortabele rechte stand kalibreren. Als de sensor ontbreekt of geweigerd wordt, kan de speler direct naar stuurknoppen wisselen. Tijdens een rit staan **Besturing wijzigen** en **Stuur recht instellen** in het pauzemenu.

Test kantelbesturing op een echte telefoon via HTTPS. Een desktopbrowser kan de schermindeling en de terugval naar stuurknoppen tonen, maar levert gewoonlijk geen bruikbare bewegingssensorgegevens.

## Publiceren via GitHub Pages

1. Stel in GitHub bij **Settings → Pages → Build and deployment** de **Source** in op **GitHub Actions**.
2. Voeg bij **Settings → Secrets and variables → Actions → Variables** de variabele `EVW_WEB_API_URL` toe. De waarde is de Worker-origin, bijvoorbeeld `https://evw-score-api.<account>.workers.dev`, zonder `/health` of ander pad.
3. Push naar `main`, of start **Build and deploy web game** handmatig via **Actions**.
4. Controleer in **Actions** dat de workflow slaagt en open daarna de Pages-site.

De workflow publiceert alleen `dist/web/`; `dist/` hoeft dus niet in Git te staan. `EVW_WEB_API_URL` bevat uitsluitend een publiek endpoint, geen geheim.

## Score-API instellen en deployen

Maak eerst de tabellen aan in de bestaande Turso-database met `server/worker/schema.sql`. Je kunt het schema ook lokaal initialiseren met `server/worker/init_db.py` en de omgevingsvariabelen `TURSO_DATABASE_URL` en `TURSO_AUTH_TOKEN`. Deel of commit deze waarden nooit.

Stel in `server/worker/wrangler.toml` bij `EVW_ALLOWED_ORIGIN` de origin van de Pages-site in. Voor een projectsite is dat bijvoorbeeld `https://gebruikersnaam.github.io`: laat het repositorypad weg. Voeg bij lokaal testen eventueel `http://localhost:8765` toe, gescheiden door een komma.

Voeg in Cloudflare bij de Worker `evw-score-api` onder **Settings → Variables and Secrets** deze waarden toe als **secrets**:

- `TURSO_DATABASE_URL`
- `TURSO_AUTH_TOKEN`

Deploy daarna vanuit de Worker-map:

```sh
cd server/worker
npx wrangler login
npx wrangler deploy
```

Als Wrangler al bij het juiste Cloudflare-account is aangemeld, kun je `npx wrangler login` overslaan. Controleer de Worker met `https://<worker>.workers.dev/health`; het antwoord hoort `{"ok":true}` te zijn.

Na een nieuwe Pages-build gebruikt de webgame de Worker voor spelers en de online ranglijst. De Worker biedt `GET /api/leaderboard?limit=10`, `POST /api/players`, `POST /api/rounds` en `GET /api/players/<id>`.

## Eindcontrole

1. Rond in de gepubliceerde webgame een rit af.
2. Controleer of de ronde in Turso is opgeslagen.
3. Open de ranglijst in een tweede browser.
4. Test een rit terwijl de API onbereikbaar is. De uitslag blijft lokaal; zodra de verbinding terug is, probeert de game de upload opnieuw.

Meer details over de lokale score-API staan in [`server/README.md`](server/README.md).
