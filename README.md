# Guildon: Map & Members 0.9.0 (WoW Forever und WoW Classic Era)

Teil von Guildon, den Addons für die Gilde: Gildenmitglieder auf der Karte, Mitgliederliste mit Klassen und Twinks, Pfeil zu einem Mitglied.
Für World of Warcraft: Forever (Client "Camelot", Interface 16001) und WoW Classic Era (Interface 11509).
Alles läuft zwischen Mitgliedern, die Guildon haben, über den Addon-Kanal der Gilde. Es gibt keinen Server.

**Neu in 0.9.0:** Guildon besteht jetzt aus Teilen. Berufe, Rezepte, Wunschliste, Handel und Post, Preise und Profitabel sind
**Guildon: Crafts & Recipes** (Ordner `Guildon_Crafts`). Map & Members braucht Crafts & Recipes und DonMap. Deine Daten aus
Guildon übernimmt Crafts & Recipes beim ersten Start von selbst. Alle Teile teilen sich einen Knopf an der Minikarte: ein Klick
zeigt die Teile zur Auswahl.

## Installation
Die Ordner `Guildon`, `Guildon_Crafts` und `DonMap` in den AddOns-Ordner des Clients kopieren (`...\Interface\AddOns\`). Nach einem
Update mit neuen Bildern das Spiel ganz neu starten, `/reload` reicht dann nicht.

## Funktionen
- **Karte:** Mitglieder mit Guildon auf Welt- und Minikarte, Punkt in Klassenfarbe mit Stufe, dicht beieinander als Gruppe mit
  Anzahl. Klick flüstert, Umschalt und Klick lädt in die Gruppe ein, Rechtsklick setzt den Pfeil. Aussehen, Größe und Deckkraft
  der Punkte einstellbar. Position teilen mit der Gilde, nur mit der Gruppe oder gar nicht; verborgen in Dungeons und bei PvP.
- **Mitglieder:** Suche und Filter, online zuerst, offline eingeklappt, Mitglieder nach Klasse als Balken. Der Tooltip zeigt Rang,
  Stufe, Guildon-Version, zuletzt gesehen und Twinks; mit Crafts & Recipes auch die Berufe.
- **Twinks:** die Charaktere eines Accounts sind verknüpft, Flüstern geht an den, der gerade online ist.
- **Wappen** der Gilde im Fensterkopf und in der Übersicht, **Pfeil** zu einem Mitglied (DonMap).
- **Allein ausprobieren:** `/gn demo` zeigt eine Beispielgilde, nur auf deinem Bildschirm.
- Englisch, Deutsch, Französisch, Spanisch (Spanien und Lateinamerika), brasilianisches Portugiesisch, Russisch, Koreanisch und
  traditionelles Chinesisch.

## Befehle
- `/gn` Fenster zeigen oder ausblenden (auch über den gemeinsamen Guildon-Knopf an der Minikarte)
- `/gn members` Mitglieder
- `/gn sync` die Gilde jetzt nach neuen Daten fragen
- `/gn demo` Beispielgilde (nochmal: aus)
- `/gn diag` Stand des Austauschs und Fehler
- `/gn help` alle Befehle
- `/gn wishes`, `/gn export` und `/gn recipes` sind jetzt in Crafts & Recipes (`/gnc`).

## Technik
- Austausch nur über Addon-Nachrichten im Gildenkanal, Daten in Stücken mit Prüfsumme, abgeholt per Flüstern. Positionen
  höchstens alle 4 Sekunden und nur, wenn jemand zuschaut, nie in Instanzen (außer mit Schalter).
- Andere Addons können Zeilen in den Mitglieder-Tooltip geben: `GuildonAPI.AddMemberLines(fn)`, fn(member) gibt eine Liste von
  Texten zurück (Crafts & Recipes: Berufe, Aufträge für die Gilde).
- Gemeinsamer Minimap-Knopf: GuildShared/Launcher.lua, jeder Teil meldet sich mit `ns.MODULE` an (GuildonLauncher.Register).

## Lizenz
Code: MIT, siehe LICENSE.txt. Autor: DonCoohd. Die Rezeptdaten (GPL v3) sind mit den Berufen nach Crafts & Recipes gegangen.
