# Guildbound

Guildbound is the working title for a fantasy guild-management game. It combines a 5E rules foundation with Football Manager-style decisions about recruitment, squad depth, and who works well together.

You start with one adventuring party taking local contracts from patrons. Recruit adventurers who cover each other's weaknesses and build enough trust to work together. As the guild grows, develop prospects, rotate members into the active roster, and build a second party without pulling the first apart.

Adventurers have recognizable 5E classes such as Paladin, Ranger, and Wizard. Party assignments such as Captain and Scout are separate decisions. Guildbound takes place in an original setting and targets desktop on Windows, macOS, and Linux.

## First prototype

Assemble one party and resolve one disputed expedition. The player chooses who goes, assigns a Captain and Scout, and decides how to respond when the Scout's report conflicts with what the patron asked for. The outcome should make it clear how those choices affected the party and what the guild carries into the next job.

### Play locally

Install [Godot 4.5.1 Standard](https://godotengine.org/download/archive/4.5.1-stable/), import `project.godot` in the Project Manager, then press **F6** with `guildhall.tscn` open or **F5** to run the project. Guildbound opens in a desktop window. The game saves the active expedition and debrief in Godot’s per-user application data directory.

Choose a third adventurer to complete the starting lineup, or replace party members before departing. The journal explains the roll and records the payout, patron standing, and changes in trust. Compare other orders using the same roll, or start a new playthrough from the journal to try a different lineup.

### Desktop builds

Install the matching Godot export templates and use **Project → Export**. The presets target macOS (Universal 2), Linux (x86-64), and Windows (x86-64). Create the corresponding subdirectories under `build/` before exporting. The Desktop prototype workflow tests the project and builds all three targets when it runs.

### Tests

From the repository root, run:

```sh
godot --headless --editor --import
godot --headless --script res://test/expedition_test.gd
godot --headless --quit-after 3
```

The prototype uses SRD 5.1 classes and ability modifiers with a Guildbound expedition check and trust system. See the [prototype brief](docs/prototype.md) and [SRD attribution](docs/attribution.md).
