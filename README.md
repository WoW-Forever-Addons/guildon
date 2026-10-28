# Guildon 0.7.0 (WoW Forever und WoW Classic Era)

Der Gildenhelfer für alles: Berufe und Rezepte der Gilde, Wunschliste mit Aufträgen, Hilfe bei Handel und Post, geteilte Auktionspreise und profitable Rezepte, Gildenmitglieder auf der Karte.
Für World of Warcraft: Forever (Client "Camelot", Interface 16001) und WoW Classic Era (Interface 11509).
Alles läuft zwischen Mitgliedern, die Guildon haben, über den Addon-Kanal der Gilde. Es gibt keinen Server.

## Installation
Ordner `Guildon` in den AddOns-Ordner des Clients kopieren (`...\Interface\AddOns\`). Nach einem Update mit neuen Bildern das Spiel ganz neu starten, `/reload` reicht dann nicht.

## Funktionen
- **Berufe und Rezepte der Gilde:** die Berufe jedes Mitglieds mit Fertigkeit, alle Rezepte eines Berufs mit Haken, wer in der Gilde es herstellen kann (grün, wenn jemand online ist), Suche, Filter, Gruppen nach Art (Rüstung nach Platz, Essen nach Buff), Reagenzien mit dem, was du hast, Flüstern an den Handwerker mit Gegenstandslink.
- **Wunschliste:** ein Rezept wünschen statt herumzufragen: Menge, "Mats habe ich", "Mats bezahle ich" oder "knapp bei Kasse", Trinkgeld, Notiz, für alle oder einen Handwerker. Handwerker sehen, was sie herstellen können, nehmen an, melden hergestellt und verschickt. Nach dem Handel oder dem Öffnen des Briefs gilt der Wunsch als erhalten. Wünsche für Sammelgut erreichen die Sammler der Gilde. Offiziere dürfen Wünsche löschen, der Gildenleiter wählt die Ränge.
- **Handel und Post:** eine Leiste unter dem Handelsfenster und im Reiter Senden des Briefkastens legt Mats oder Ware eines Auftrags ein (ein Stapel je Klick), füllt den Brief aus und setzt die Nachnahme. Handel annehmen und Brief abschicken machst du selbst.
- **Preise und profitable Rezepte:** Preise aus Auctionator, Auctioneer oder aux werden mit der Gilde geteilt (der neueste Scan zählt, Ausreißer sind markiert). Ohne AH-Addon ein kurzer Scan im Auktionshaus. Der Reiter Profitabel ordnet Rezepte nach Gewinn je Herstellung.
- **Karte:** Mitglieder mit Guildon auf Welt- und Minikarte, Punkt in Klassenfarbe mit Stufe, dicht beieinander als Gruppe mit Anzahl. Klick flüstert, Umschalt und Klick lädt in die Gruppe ein. Aussehen, Größe und Deckkraft der Punkte einstellbar. Position teilen mit der Gilde, nur mit der Gruppe oder gar nicht; verborgen in Dungeons und bei PvP.
- **Und mehr:** Abklingzeiten der Gilde (Transmutieren, Mondstoff, Salzstreuer), "Rezept gesucht" mit Tooltipzeilen auf Rezeptgegenständen, Einkaufslisten, Hinweis, wenn ein Handwerker für deinen Wunsch online kommt, verknüpfte Twinks, Mitglieder-Tooltips mit Berufen, Mitglieder nach Klasse, Dank-Zähler, Questdons Pfeil zu einem Mitglied, "In der Gilde hergestellt von" im Gegenstands-Tooltip, Export deiner Berufe für die Gildenseite.
- **Allein ausprobieren:** `/gn demo` zeigt eine Beispielgilde, nur auf deinem Bildschirm.
- Englisch, Deutsch, Französisch, Spanisch (Spanien und Lateinamerika), brasilianisches Portugiesisch, Russisch, Koreanisch und traditionelles Chinesisch.

## Befehle
- `/gn` Fenster zeigen oder ausblenden (auch über den Knopf an der Minikarte)
- `/gn members` Mitglieder
- `/gn wishes` Wunschliste
- `/gn sync` die Gilde jetzt nach neuen Daten fragen
- `/gn demo` Beispielgilde (nochmal: aus)
- `/gn export` deine Berufe als Text für die Gildenseite
- `/gn recipes` Rezepte, die das Spiel gezeigt hat und Guildon noch nicht kennt, als Text für die Guildon-Autoren
- `/gn diag` Stand des Austauschs und Fehler
- `/gn help` alle Befehle

## Technik
- Austausch nur über Addon-Nachrichten im Gildenkanal, Daten in Stücken mit Prüfsumme, abgeholt per Flüstern. Positionen höchstens alle 4 Sekunden und nur, wenn jemand zuschaut, nie in Instanzen (außer mit Schalter).
- Handel und Post: Guildon legt Gegenstände nur nach deinem Klick ein. Annehmen und Senden bleiben bei dir.
- Preise der AH-Addons über deren öffentliche Schnittstellen, jeder Aufruf geschützt (pcall).
- Rezeptdaten aus All The Things (MIT) und CMaNGOS classic-db (GPL v3), für Forever und Era. Lager-Rezepte für Forever: Data from ForeverDB.net (https://foreverdb.net), GPL v3.

## Lizenz
Code: MIT, siehe LICENSE.txt. Rezeptdaten (Data/Recipes.lua, DataEra/Recipes.lua): GPL v3, weil sie aus CMaNGOS gebaut sind, Text in Data/Recipes-LICENSE-GPLv3.txt. Das Addon als Ganzes steht damit unter GPL v3. Autor: DonCoohd.
