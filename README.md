# Wardrobe Loadouts

![Wardrobe Loadouts preview](preview.gif)

Source repository: https://github.com/Maeiro/WardrobeLoadouts

Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3841263981

A local mod for Project Zomboid Build 42.22.2 that stores equipment sets in wardrobes and equips another set using the game's inventory actions.

## Features

- Open the loadout manager from container controls, the right-click menu, or Viewpoint interactions while aiming at furniture. Supported furniture includes wardrobes, dressers, lockers, and military lockers.
- Store the current equipment physically inside the wardrobe and save its loadout. Captured equipment includes clothing, enabled wearable bags, hand items, and items attached to belt and holster slots.
- Use fixed slots, including empty ones, without manually creating or naming loadouts. **Swap** equips a slot and stores your current equipment in it; **Take** equips the slot and empties it. Items are moved as their original inventory instances, never copied.
- Keep slots in the wardrobe's mod data. Existing loadouts are assigned stable slots automatically, and an already worn legacy loadout can be stored in its existing slot.
- Use the slot definitions loaded by the game when restoring equipment, including slots added by other mods.

## Local installation

Run `tools/Build.ps1` with JDK 25 and the Viewpoint API 1.0. Use `-JdkDir` and `-ViewpointApiJar` to specify their locations; the script uses configured local installations when omitted. The addon is compiled with `--release 17` and does not bundle API classes. Extract `dist/WardrobeLoadouts.zip` to `C:\Users\<USERNAME>\Zomboid\Workshop` or copy the `dist/WardrobeLoadouts` folder there. Keep this structure:

```text
WardrobeLoadouts/
└── Contents/
    └── mods/
        └── WardrobeLoadouts/
            ├── mod.info
            └── 42/
                ├── mod.info
                └── media/...
```

Enable **Wardrobe Loadouts** in the Mods menu. For multiplayer, install and enable the package on the server and every client. Loadout data is stored in the world's wardrobe and remains after restarting.

To release the mouse while using Viewpoint cameras, restart the game once after installation and enable **Wardrobe Loadouts Cursor** under **Viewpoint → Advanced → Addons**, then approve the **camera** and **lua** permissions. This small optional Java addon uses the API 1.0 `CursorClaim`. While the manager is open, the mouse is free and will not turn the camera. Closing the manager releases only this addon's claim, preserving other windows' requests. If the manager disappears without closing normally, its claim expires after two seconds without a heartbeat. The Lua manager also works without this addon or Viewpoint. Subsequent Lua-only UI changes can be applied with the game's Lua reload.

## Usage

1. Open a wardrobe container and select **Manage Loadouts**, including through Viewpoint interactions.
2. Select an empty slot and click **Store** to move your current equipment into it. The slot gets a default name.
3. On an occupied slot, click **Swap** to equip its items and store your current equipment in that same slot.
4. Click **Take** to equip the slot without storing your previous equipment. Replaced items stay in your inventory and the slot becomes empty.
5. Double-click an empty slot to store your equipment, or an occupied slot to swap loadouts. A single click only selects a slot.
6. Select a slot to inspect its item icons and order before acting. The buttons apply to the selected slot. **Rename**, beside the title, changes the slot name, including for empty slots; the name persists after taking or swapping a loadout. Hover over **?** for settings guidance.

Hover over an item to see its full name. Missing items appear in red and prevent a swap until they are available. The number of slots follows the existing Sandbox option, which defaults to 12. Reducing the limit does not hide already stored loadouts. In multiplayer, slots are shared and only change after the server verifies the item transfer.

## Configuration

Sandbox options are shared and should be set by the host or server:

- **Maximum loadouts per wardrobe**: 1–24, default 12.
- **Switch duration**: 0–10 seconds, default 0.
- **Wardrobe capacity for loadout storage**: capacity 50–100, default 100.
- **Save and switch hand items**: includes both hands, enabled by default.
- **Save and switch wearable bags**: includes worn bags, enabled by default.
- **Save and restore belt, holster, and other attached items**: saves attached equipment slots, enabled by default.

When a category is disabled, loadouts ignore it and leave the current equipment as is. Previously saved items in a category are included again if the option is re-enabled; loadouts stored while it is disabled do not capture those items.

Under **Options → Mods → Wardrobe Loadouts**, adjust the interface scale and language. Language can follow the game automatically or be selected from EN, ES, FR, DE, IT, PT, PT-BR, RU, CN, UA, KO, JP, and TR. The **- / +** buttons beside **?** adjust the scale in 5% steps and save the client preference.

**Diagnostic logs** are off by default and can be toggled without restarting. When enabled, they record store and swap details and cursor status, and monitor for 20 seconds to see whether items return to the furniture after a swap. This monitoring does not run while diagnostics are off. Player-facing error messages remain available either way.

The language selector uses English names and codes so it remains readable with any game font. Interface translations are in `42/media/lua/shared/Translate/EN/UI.json`, with per-language keys read by the game's native translator to preserve Unicode. PZ 42.22.2 requires JSON translation files such as `UI.json`, `IGUI.json`, and `Sandbox.json`. Do not put Unicode text directly in Lua string literals: this game's Lua compiler corrupts it. Restart the game after adding translation files; once loaded, language changes update the open window without restarting.

The **Icon** button beside **Rename** opens a searchable catalogue of loaded item icons, including modded items. It also accepts the name or path of another texture available in the game. **Automatic** restores the icon chosen from the slot's contents. Slot names and icons remain after taking a loadout.

Parts of the same piece of furniture share loadouts, item lookup, and the configured storage limit. They are linked using the native sprite grid and the object's internal containers; nearby furniture is not grouped by distance. Physical containers and item transfers remain game-managed. Existing loadouts from both parts are preserved, with IDs and slots remapped when needed.

Viewpoint API 1.0 does not document a dedicated loot-panel button registration. Access uses `OnFillWorldObjectContextMenu` with the furniture itself as the explicit target, which the installed Viewpoint interaction collector recognizes. Releasing the cursor uses the optional Java addon described above; Viewpoint and Smarter Storage are not required to use the wardrobe manager.

## Compatibility and limitations

The mod does not depend on specific slot names: restoration checks the slots available after equipping the loadout. This lets Alice's Weapon Sling, Vanilla Gear Expanded, Simple Flashlight on Belt, and Swap It use their own slot registrations. Each mod combination still needs in-game verification.

The mod does not duplicate items, create Lua network files, or modify other mods. If an action is interrupted or a slot is unavailable for an item, the items remain in the inventory or wardrobe and the swap is marked incomplete. Correct the equipment manually before retrying.

## In-game checks

Store two different loadouts, including one item in each hand and an item in a holster or belt. Confirm that the items move into the wardrobe and that your character is left without the stored equipment. Equip each loadout in turn and check the order of attached items. Restart the world and confirm names and items persist. In multiplayer, repeat with two characters and confirm one character's active set does not affect the other. Also check an Alice's Weapon Sling item, a Simple Flashlight on Belt item, and Vanilla Gear Expanded equipment.

Open the manager from the right-click menu and while aiming through Viewpoint. Store a set, choose its name and icon, take it from the other half of the same furniture, and confirm persistence. Check a dresser and a locker, the scale controls, and language selection in client options. Automated validation uses simulated ISUI surfaces and entities; final alignment and SP/MP transfers need in-game checks.

With **Wardrobe Loadouts Cursor** enabled, open the manager in first person and move the mouse: the pointer should operate the window without turning the camera. Open and close the icon picker; closing the manager should return camera control. Check the **- / + / ? / X** buttons at different scales and confirm the rounded picker has no text bleeding through from the main window.
