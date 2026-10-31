local _, ns = ...
if GetLocale() ~= "deDE" then return end
local L = ns.L

L["Overview"] = "Übersicht"
-- tab label, short (Daniel 26.10.: the long word was cut off in the tab bar)
L["Members"] = "Mitglieder"
L["Map"] = "Karte"
L["Options"] = "Optionen"
L["%d days ago"] = "vor %d Tagen"
L["%d h ago"] = "vor %d Std."
L["%d min ago"] = "vor %d Min."
L["/gn shows it again."] = "/gn zeigt es wieder."
L["Asked the guild for new data."] = "Die Gilde wurde nach neuen Daten gefragt."
L["Commands:"] = "Befehle:"
L["Dim in combat"] = "Im Kampf abdunkeln"
L["Guildon %s"] = "Guildon %s"
L["Guildon shows your guild once you join one."] = "Guildon zeigt deine Gilde, sobald du in einer bist."
L["Hide window"] = "Fenster ausblenden"
L["Lock window"] = "Fenster sperren"
L["No data from the guild yet."] = "Noch keine Daten aus der Gilde."
L["Offline (%d)"] = "Offline (%d)"
L["Online (%d)"] = "Online (%d)"
L["Reset window position"] = "Fensterposition zurücksetzen"
L["The guild list is loading."] = "Die Gildenliste wird geladen."
L["Unknown command: %s"] = "Unbekannter Befehl: %s"
L["You are not in a guild."] = "Du bist in keiner Gilde."
L["Your rank: %s"] = "Dein Rang: %s"
L["an error occurred, /gn diag for details"] = "ein Fehler ist aufgetreten, /gn diag zeigt Einzelheiten"
L["offline"] = "offline"
L["without Guildon"] = "ohne Guildon"
L["show or hide the window"] = "Fenster zeigen oder ausblenden"
L["the guild members"] = "die Gildenmitglieder"
L["ask the guild for new data now"] = "die Gilde jetzt nach neuen Daten fragen"
L["state of the exchange and errors"] = "Stand des Austauschs und Fehler"
L["this list"] = "diese Liste"

-- Schritt 2: Berufe und Rezeptbuch
L["Click: whisper"] = "Klick: anflüstern"
L["Search"] = "Suche"

-- Beispielgilde (/gn demo)
L["Example guild"] = "Beispielgilde"
L["Member"] = "Mitglied"
L["Example member"] = "Beispielmitglied"
L["example guild to try the windows (again: off)"] = "Beispielgilde zum Ausprobieren der Fenster (nochmal: aus)"
L["Example member, only on your screen (/gn demo off)."] = "Beispielmitglied, nur auf deinem Bildschirm (/gn demo off)."
L["Example guild is on: the members ending in -Demo are made up and only on your screen. /gn demo off removes them."] = "Beispielgilde an: die Mitglieder mit -Demo sind erfunden und nur auf deinem Bildschirm. /gn demo off entfernt sie."
L["Example guild on: %d made-up members ending in -Demo, only on your screen. /gn demo off removes them."] = "Beispielgilde an: %d erfundene Mitglieder mit -Demo, nur auf deinem Bildschirm. /gn demo off entfernt sie."
L["Example guild off."] = "Beispielgilde aus."
L["%s is an example member and cannot be whispered."] = "%s ist ein Beispielmitglied und kann nicht angeflüstert werden."

-- Rezeptbuch: Arten, Dropdowns, Kochkunst nach Buff
L["Click: choose"] = "Klick: auswählen"

-- Layout-Durchsicht 25.10.
L["Hide the example guild"] = "Beispielgilde ausblenden"
L["Show an example guild"] = "Beispielgilde zeigen"
L["Your characters"] = "Deine Charaktere"
L["Window size"] = "Fenstergröße"

-- Website export (25.10.2026)

-- Wish list (step 3, 25.10.2026)
L["Every member who has Guildon shows up here."] = "Jedes Mitglied mit Guildon erscheint hier."
L["Drag: wider or narrower, more or fewer lines."] = "Ziehen: breiter oder schmaler, mehr oder weniger Zeilen."
L["Shift and drag: make everything bigger or smaller."] = "Umschalt und Ziehen: alles größer oder kleiner."

-- Trade and mail (step 4)

-- Prices and profitable (step 5)

-- Map (step 6)
L["With the guild"] = "Mit der Gilde"
L["Only with my group"] = "Nur mit meiner Gruppe"
L["Off"] = "Aus"
L["Share my position"] = "Meine Position teilen"
L["Hide while flagged for PvP"] = "Bei PvP-Markierung verbergen"
L["Members on the world map"] = "Mitglieder auf der Weltkarte"
L["Members on the minimap"] = "Mitglieder auf der Minikarte"
L["Minimap in dungeons and raids"] = "Minikarte in Dungeons und Schlachtzügen"
L["Off by default. On: inside a dungeon or raid you share your place and see the members with Guildon on the minimap, as far as the game gives positions there."] = "Standardmäßig aus. An: in Dungeons und Schlachtzügen teilst du deinen Standort und siehst die Mitglieder mit Guildon auf der Minikarte, soweit das Spiel dort Positionen liefert."
L["Only members with Guildon can be shown; in dungeons and raids only with the switch above."] = "Nur Mitglieder mit Guildon erscheinen; in Dungeons und Schlachtzügen nur mit dem Schalter oben."
L["Members by class"] = "Mitglieder nach Klasse"
L["Click: show only this class"] = "Klick: nur diese Klasse zeigen"
L["Map icon size"] = "Größe der Kartensymbole"
L["Minimap icon size"] = "Größe der Minikartensymbole"
L["Size of the guild pins on the world map. 100 % is the normal size."] = "Größe der Gildensymbole auf der Weltkarte. 100 % ist die normale Größe."
L["Size of the guild pins on the minimap. 100 % is the normal size."] = "Größe der Gildensymbole auf der Minikarte. 100 % ist die normale Größe."
L["No member with Guildon is sharing a position right now."] = "Gerade teilt kein Mitglied mit Guildon seine Position."
L["%d s ago"] = "vor %d s"
L["Click: show on the world map"] = "Klick: auf der Weltkarte zeigen"
L["Level %d"] = "Stufe %d"

-- Extras (step 7)
L["%s is offline; whispering the alt %s."] = "%s ist offline; flüstere den Twink %s an."
L["Alts: %s"] = "Twinks: %s"
L["Last seen: %s"] = "Zuletzt gesehen: %s"
L["Right-click: arrow to this member"] = "Rechtsklick: Pfeil zu diesem Mitglied"
L["today"] = "heute"
L["Minimap button"] = "Knopf an der Minikarte"
L["Layer: unknown"] = "Layer: unbekannt"
L["Layer %d"] = "Layer %d"
L["(same as yours)"] = "(wie deiner)"
L["(not yours)"] = "(nicht deiner)"
L["%d guild members here"] = "%d Gildenmitglieder hier"
L["Shift-click: invite to your group"] = "Umschalt+Klick: in die Gruppe einladen"
L["%s is an example member and cannot be invited."] = "%s ist ein Beispielmitglied und kann nicht eingeladen werden."
L["%d members"] = "%d Mitglieder"
L["All"] = "Alle"
L["Classic Era"] = "Classic Era"
L["Data sets"] = "Datensätze"
L["Game version"] = "Spielversion"
L["Guildon only"] = "Nur Guildon"
L["Last data from the guild"] = "Letzte Daten aus der Gilde"
L["Makes the window see-through during combat."] = "Macht das Fenster im Kampf durchsichtig."
L["Minimap"] = "Minikarte"
L["My zone"] = "Meine Zone"
L["Nobody found."] = "Niemand gefunden."
L["Show"] = "Anzeigen"
L["Stops the window from being moved."] = "Verhindert, dass das Fenster verschoben wird."
L["Window"] = "Fenster"
L["With Guildon"] = "Mit Guildon"
L["WoW Forever"] = "WoW Forever"
L["click to show"] = "Klick zum Anzeigen"
L["online: %d"] = "online: %d"
L["Yours: %s"] = "Deine: %s"
L["Yours: nothing yet"] = "Deine: noch nichts"
-- (26.10.) automatic receipt, pin looks
L["Pin look"] = "Aussehen der Pins"
L["Guild sign"] = "Gildenzeichen"
L["Shield only"] = "Nur Schild"
L["Plain dot"] = "Schlichter Punkt"
-- (27.10.) pin opacity
L["Opacity"] = "Deckkraft"
L["How see-through the guild pins on the world map and the minimap are. 100 % is fully visible."] = "Wie durchsichtig die Gildenpins auf Weltkarte und Minikarte sind. 100 % ist voll sichtbar."
-- (27.10.) layer switch, group count
L["%dx"] = "%dx"
L["Show the layer"] = "Layer anzeigen"
L["The layer (server copy of the zone) of each member in the tooltips and lists, compared with yours. Off by default."] = "Der Layer (Serverkopie der Zone) jedes Mitglieds in Tooltips und Listen, verglichen mit deinem. Standard aus."

-- (31.10.2026, Guildon 0.9 and Guildon Crafts 1.0)
L["Coming in a later version of %s."] = "Kommt in einer späteren Version von %s."
L["Click: open Guildon Crafts"] = "Klick: Guildon Crafts öffnen"
L["Guildon Crafts is not loaded: professions, recipes and wishes are in it."] = "Guildon Crafts ist nicht geladen: Berufe, Rezepte und Wünsche sind darin."
L["How it works: 1. Join a guild. 2. Members with Guildon show up by themselves. 3. You see them on the map and in the member list."] = "So geht es: 1. Tritt einer Gilde bei. 2. Mitglieder mit Guildon erscheinen von selbst. 3. Du siehst sie auf der Karte und in der Mitgliederliste."
L["Professions and wishes: Guildon Crafts"] = "Berufe und Wünsche: Guildon Crafts"
L["Professions and wishes: Guildon Crafts is not loaded"] = "Berufe und Wünsche: Guildon Crafts ist nicht geladen"
L["Professions, recipes, wish list and trade of the guild."] = "Berufe, Rezepte, Wunschliste und Handel der Gilde."
L["This is in Guildon Crafts now: /gnc %s"] = "Das ist jetzt in Guildon Crafts: /gnc %s"
L["Click: choose a part. Drag: move."] = "Klick: Teil wählen. Ziehen: verschieben."
L["Click: open the window. Drag: move."] = "Klick: Fenster öffnen. Ziehen: verschieben."
L["Shows the Guildon button at the minimap. All Guildon parts share it."] = "Zeigt den Guildon-Knopf an der Minikarte. Alle Guildon-Teile teilen sich ihn."
