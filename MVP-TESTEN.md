# EVW Game MVP testen

## Windows op het werk

Pak `EVW-MVP-Windows.zip` uit in **één map op de netwerkschijf**. Iedereen
start `EVW Game.exe` vanuit diezelfde map. De `.exe`, `.pck` en `scoremap.txt`
moeten bij elkaar blijven. De game maakt automatisch de submap `scores` naast
de `.exe` aan en schrijft daarin één JSON-bestand per voltooide rit. Alle
spelers moeten lees- en schrijfrechten op die map hebben. De ranglijst leest
de ritbestanden van deze gedeelde map.

## macOS testen

Pak `EVW-MVP-macOS.zip` uit en start `EVW GAME.app`. De app, `scoremap.txt`
en de submap `scores` staan naast elkaar. Zonder netwerkschijf test je hiermee
dezelfde opslaglogica op je Mac; de ranglijst is dan alleen lokaal gedeeld
tussen gameprocessen die deze map gebruiken. Deze MVP is niet genotariseerd;
macOS kan bij de eerste start vragen om de app via de beveiligingsinstellingen
expliciet te openen.

## Andere scoremap gebruiken

In `scoremap.txt` staat standaard `scores`: een map naast de game. Je kunt
die regel vervangen door een absoluut pad, bijvoorbeeld `Z:/EVW/scores` op
Windows of `/Volumes/Bedrijf/EVW/scores` op macOS. Op beide platforms mag
de omgevingsvariabele `EVW_SHARED_SCORES_DIR` het bestand overschrijven.

Elke uitslag wordt eerst in Godots eigen `user://scores.json` op de computer
opgeslagen. Is de gedeelde map tijdelijk onbereikbaar, dan blijft de uitslag
daar staan. De game probeert opnieuw bij het opstarten, bij het openen van
de ranglijst en elke 30 seconden. De ranglijst toont lokale resultaten als
de gedeelde map onbereikbaar is. Bewaar regelmatig een kopie van de gedeelde
`scores`-map.

De Windows-build is op macOS gegenereerd en op bestandsformaat gecontroleerd;
het uitvoeren van de `.exe` moet op een Windows-computer worden getest.
