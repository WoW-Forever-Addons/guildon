# Changes

## 0.9.2
- **Guild crest on the shield pin:** the crest now sits on a smaller shield in your guild's colour instead of a square, so the class colour stays a closed ring around it and the crest is in the middle.

## 0.9.1
- **Guildon: Crafts & Recipes is now optional.** Map & Members only needs DonMap. Install Crafts & Recipes if you want professions, recipes and wishes, and the professions in the member tooltips; your old Guildon data moves over at its first start.

## 0.9.0
- **New required addons: Guildon: Crafts & Recipes and DonMap.** The CurseForge app installs both for you. If you install by hand, download them too and put the folders `Guildon_Crafts` and `DonMap` next to `Guildon` in `Interface\AddOns`, or Guildon does not load.
- Professions, recipes, the wish list, trade and mail help, prices and Profitable are now an addon of their own: **Guildon: Crafts & Recipes** (folder Guildon_Crafts). This one is now **Guildon: Map & Members**. Crafts & Recipes takes over your professions, wishes and prices from Guildon at its first start, and still talks to guild members on Guildon 0.8.
- Guildon keeps the guild map, the member list with classes and alts, the guild emblem and the arrow to a member. With Crafts & Recipes the member tooltips show the professions again.
- One minimap button for all Guildon parts: a click shows the parts to choose from. The overview has a tile that opens Crafts & Recipes. /gn wishes, /gn export and /gn recipes point to /gnc.
- The map pins are drawn by DonMap, the map layer of the Don addons, and look as before. Right-click a member to set the arrow, also without Questdon.
- **Much less guild traffic:** your position only goes to members who look at a map near you (world map open, or the minimap within 800 yards), and every 60 seconds while you stand still; data of members who left the guild is dropped after 30 days; up to 8 messages go at once, then one per second, and messages that have to wait are sent later instead of being lost.
- Window style from DonCore, the common base of the Don addons.

## 0.8.2
- The tab Profitable is now off by default, so the window stays focused on the guild. Switch it on in Options, section Tabs.

## 0.8.1
- A recipe someone in the guild wants drops for you: a chat line names who wants it (click the name to whisper), and the ones who want it read who found it. Only for your own loot, in addition to the tooltip line.

## 0.8.0
- About 440 more WoW Forever recipes: the new Forever recipes from the game client data and the specialisation recipes (Armorsmith, Weaponsmith, Dragonscale, Elemental, Tribal, Gnomish, Goblin).
- Recipes the game shows that Guildon's data lacks (also ones you have not learned yet, the WoW Forever profession window lists them all) now appear in the recipe book with their reagents, and recipes known without reagents take them from the game. New command /gn recipes shows them as text to send to the authors.
- Camp recipes for WoW Forever complete with skill and reagents, and Herbalism, Skinning and Fishing now have a recipe book (Incense Candle, Greenhouse, Seed Hybridizer, Camp Chair, Field Guide, Trapper's Workbench, Fish Bowl, Fishing Rack, Fishing Hut). Camp data from ForeverDB.net (https://foreverdb.net).
- Recipes you have not learned yet that your profession window shows are shared with the guild, so everyone sees them in the recipe book and in /gn recipes.

## 0.7.0 (first version for testers)

- Removed the test commands /gn libra, /gn crest and /gn prices. /gn demo and /gn diag stay.
- Wishes are marked received on their own when the crafter's goods come in a trade or when you open the crafter's letter with them, so the list stays short in big guilds.
- Choose the look of the map pins (Map tab, with a preview): guild sign, shield only or a plain dot, always in the class colour.
- Fixed: in the wish form a long hint ("Nobody in the guild knows it yet ...") no longer covers the reagents; the form grows instead.
- Fixed: the Map tab counted "0 members" while the zones were closed.
- Fixed: in the options a description over two lines no longer covers the next row.
- Fixed: reagent names that the game sends later ("Item 2835") now show up in the open wish form.
- Example guild: the members of the list no longer walk along with you on the map; the travellers in many zones stay.

Guildon is the guild's all-in-one helper for WoW Forever and WoW Classic Era. Everything works between members who have Guildon; there is no server, the data travels through the guild's addon channel.

- **Professions and recipes of the guild:** every member's professions with skill, all recipes of a profession with a mark who in the guild can craft them (green when someone is online), search, filters, groups by type (armour by slot, food by buff), reagents with what you have, whisper the crafter with the item link.
- **Wish list:** wish a recipe instead of asking around: amount, "I bring the reagents", "I pay for the reagents" or "short of money", tip, note, for everyone or one crafter. Crafters see the wishes they can craft, accept, mark crafted and sent; you mark it received. Wishes for gathered goods reach the guild's gatherers. Officers may delete wishes; the guild master chooses which ranks count as officers.
- **Trade and mail:** a bar below the trade window and the mailbox puts in the reagents or the goods of an order, one stack per click, fills in the letter and cash on delivery. You accept the trade and send the letter yourself.
- **Prices and profitable crafts:** prices from Auctionator, Auctioneer or aux are shared with the guild (the newest scan counts, odd prices are marked); without an AH addon a short scan at the auction house. The tab Profitable lists recipes by profit per craft (off by default, switch it on in the options).
- **Map:** members with Guildon on the world map and the minimap, a dot in class colour with the level. Share your position with the guild, only with your group, or not at all; hidden in dungeons and when flagged for PvP.
- **And more:** guild cooldowns (transmute, Mooncloth, Salt Shaker), "recipe wanted" with tooltip lines on recipe items, shopping lists, a note when a crafter for your wish comes online, alts linked, member tooltips with professions, the guild emblem, a thanks counter, Questdon's arrow to a member, "crafted in the guild by" in item tooltips, an export of your professions for the guild website (`/gn export`).
- **Try it alone:** `/gn demo` shows an example guild (only on your screen).
- **Your language:** English, German, French, Spanish, Brazilian Portuguese, Russian, Korean and Traditional Chinese.
