# Guildbound

Guildbound is the working title for a fantasy guild-management game. It combines a 5E rules foundation with Football Manager-style decisions about recruitment, squad depth, and who works well together.

You start with one adventuring party taking local contracts from patrons. Recruit adventurers who cover each other's weaknesses and build enough trust to work together. As the guild grows, develop prospects, rotate members into the active roster, and build a second party without pulling the first apart.

Adventurers have recognizable 5E classes such as Paladin, Ranger, and Wizard. Party assignments such as Captain and Scout are separate decisions. Guildbound takes place in an original setting and targets desktop on Windows, macOS, and Linux.

## Alder Vale prototype

Choose local contracts from the quest map and send out one party at a time. Assemble three adventurers and assign a Captain and Scout to see each plan’s success odds. Offers close on their listed day and are replaced as patrons withdraw them or rival guilds finish the work.

### Play locally

Install [Godot 4.5.1 Standard](https://godotengine.org/download/archive/4.5.1-stable/), import `project.godot` in the Project Manager, then press **F6** with `guildhall.tscn` open or **F5** to run the project. Guildbound opens in a desktop window. The game saves the active expedition and debrief in Godot’s per-user application data directory.

The game opens paused, with fresh offers and your active expedition intact. Click **Resume** to advance one game day every 10 seconds. Each expedition takes time to reach the site, carry out the chosen plan, and travel home. The clock pauses when the Scout reports and when the party returns. The journal records the outcome, fee, standing, and trust changes. You can compare an alternative plan using the same roll.

### AI-written quests

Run [Ollama](https://ollama.com/download) on the same computer with a local chat model installed, for example `ollama pull qwen2.5:7b`. Guildbound discovers the model at startup and writes new contracts using Alder Vale lore, the calendar, and recent expedition outcomes. Use `GUILDBOUND_OLLAMA_MODEL` to select a specific installed model when launching from a terminal.

Procedural offers are available immediately and while Ollama is unavailable. AI-written stories replace unopened offers as they arrive. **Reconnect AI** checks for Ollama again from the quest map.

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

The prototype uses SRD 5.1 classes and ability modifiers with a Guildbound expedition check and trust system. See the [prototype brief](docs/prototype.md) and [SRD attribution](docs/attribution.md).
