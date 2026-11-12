# Guildbound

Guildbound is the working title for a fantasy guild-management game. It combines a 5E rules foundation with Football Manager-style decisions about recruitment, squad depth, and who works well together.

You start with one adventuring party taking local contracts from patrons. Recruit adventurers who cover each other's weaknesses and build enough trust to work together. As the guild grows, develop prospects, rotate members into the active roster, and build a second party without pulling the first apart.

Adventurers have recognizable 5E classes such as Paladin, Ranger, and Wizard. Party assignments such as Captain and Scout are separate decisions. Guildbound takes place in an original setting and targets desktop on Windows, macOS, and Linux.

## Alder Vale prototype

Write a charter and pick three founders when starting a campaign. The Quest Map has town jobs, regional commissions, independent leads, and two three-chapter quest lines. Zoom with the mouse wheel or the map controls and drag to pan. Offers close on their listed day.

The Roster opens each adventurer’s character sheet and loadout. Expeditions award XP, and successful parties bring loot back to the Armory. Spend guild gold in the Town Shop, equip gear from the stash, or sell surplus items. Use Recruitment to send an available guild member to find candidates. The Guildhall tracks each patron’s standing and the progress of the quest lines.

### Play locally

Install [Godot 4.5.1 Standard](https://godotengine.org/download/archive/4.5.1-stable/), import `project.godot` in the Project Manager, then press **F6** with `guildhall.tscn` open or **F5** to run the project. Guildbound opens in a desktop window. Campaigns save in Godot’s per-user application data directory. Existing saves keep their roster, journal and active expedition. Guildhall → Start a new playthrough resets the current campaign and opens the founding charter.

The game opens paused, with fresh offers and your active expedition intact. Click **Resume** to advance one game day every 10 seconds. Regional expeditions include travel, fieldwork, and the return trip. Town quests only advance fieldwork days. The clock pauses when the Scout reports and when the party returns. The journal records the outcome, fee, standing, and trust changes. You can compare an alternative plan using the same roll.

### AI-written quests

Run [Ollama](https://ollama.com/download) on the same computer with a local chat model installed, for example `ollama pull qwen2.5:7b`. Guildbound discovers the model at startup and writes new contracts using Alder Vale lore, the calendar, and recent expedition outcomes. Use `GUILDBOUND_OLLAMA_MODEL` to select a specific installed model when launching from a terminal.

Procedural offers are available immediately and while Ollama is unavailable. AI-written stories replace unopened standalone offers as they arrive. Quest-line chapters follow their authored stories. **Reconnect AI** checks for Ollama again from the quest map.

### Desktop builds

Install the matching Godot export templates and use **Project → Export**. The presets target macOS (Universal 2), Linux (x86-64), and Windows (x86-64). Create the corresponding subdirectories under `build/` before exporting. The Desktop prototype workflow tests the project and builds all three targets when it runs.

The macOS workflow download is a single `Guildbound-macOS.zip`. Extract it and open `Guildbound.app`. Prototype builds use ad-hoc signing. If Gatekeeper prompts on first launch, macOS offers an app-specific **Open Anyway** button in **System Settings → Privacy & Security** after a launch attempt. [Apple Support](https://support.apple.com/en-us/102445)

### Tests

From the repository root, run:

```sh
godot --headless --editor --import
godot --headless --script res://test/expedition_test.gd
godot --headless --quit-after 3 -- --no-local-ai
```

Character sheets use SRD 5.1 experience thresholds, proficiencies, hit dice, ability increases, equipment statistics, and class progression. Expeditions resolve using Guildbound’s party checks and trust system. See the [prototype brief](docs/prototype.md) and [SRD attribution](docs/attribution.md).
