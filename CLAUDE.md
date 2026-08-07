# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

灵农修仙 (LingNong Xiuxian) is a Godot 4.x 2D single-player incremental farming/cultivation prototype. The current implementation is a small runnable vertical slice; `docs/GDD-v0.1.md` and `docs/IMPLEMENTATION-PLAN-v0.1.md` describe the broader demo/production target and should be treated as the design baseline when extending the prototype.

## Commands

Run these from the repository root (`/Users/chengwen/increase`), with Godot available as `godot` (currently `/opt/homebrew/bin/godot`, Godot 4.7.1):

```bash
# Open the project in the editor
godot --editor --path .

# Run the main scene
godot --path .

# Validate project loading and script parsing without opening a window
godot --headless --path . --editor --quit

# Run the project headlessly (useful for startup/runtime smoke checks)
godot --headless --path . --quit
```

There is currently no package manager, build script, linter configuration, or automated test suite in the repository. Therefore there is no project-specific lint command or single-test command yet. For a functional check, launch the main scene and exercise planting, harvesting, breakthrough, spell actions, insect handling, reincarnation, and save/load through the UI.

## Repository structure and architecture

- `project.godot` is the project entry point. It sets `scenes/main/main.tscn` as the main scene and registers the two autoload singletons `GameState` and `SaveManager`.
- `scenes/main/main.tscn` is intentionally thin: it defines the root `Control`, background, layout containers, labels, and the two static action buttons. Most field/action UI is created dynamically by the UI script.
- `scripts/autoload/game_state.gd` is the authoritative gameplay model and simulation. It owns currencies, cultivation realms, unlocked fields, crop dictionaries, seasons, temporary events, insect events, guardian-array state, spells, reincarnation, and practitioner upgrades. It exposes state changes through `state_changed` and realm changes through `realm_changed`.
- `scripts/ui/main.gd` is the controller/view for the prototype. It loads the save on startup, builds field buttons and action buttons, translates clicks into `GameState` calls, refreshes labels/buttons, advances the simulation each frame via `GameState.update_world(delta)`, and autosaves every 30 seconds. Keep gameplay rules out of this script as systems grow.
- `scripts/autoload/save_manager.gd` serializes the relevant `GameState` fields to JSON at `user://lingnong_save.json`. `SAVE_VERSION` is currently `5`; the version-5 fields `crop_inventory` and `pills` default when loading older saves, and typed runtime arrays are rebuilt element-by-element for compatibility.
- `.godot/` is generated Godot editor/import state and should not be treated as source. `.uid` files beside scripts are Godot-generated metadata.

The runtime flow is:

1. Godot loads `main.tscn` and initializes the autoloads.
2. `GameState._ready()` creates a new-game structure; `main.gd` then calls `SaveManager.load_game()`.
3. UI clicks mutate the model through `GameState` methods and usually save immediately.
4. Each frame, `main.gd` calls `GameState.update_world(delta)` for seasons, random events, lifespan, and insect timing, then refreshes the UI.
5. `GameState.state_changed` also triggers UI refreshes after model mutations.

Use Unix timestamps for persisted/real-time timers, as the current model does. The current vertical-slice balance is 3 field slots, only the `聚灵草` crop in the UI, 5-second growth, 5-stone crop sale, 5-stone `聚气丹`, 50 cultivation per pill, realm thresholds 50/500/5000 for 炼气/筑基/金丹, 180-second season/event timing, 60-second random events, 10-灵气 `灵雨诀`, 20-灵气/120-second-cooldown `庚金剑诀`, and guardian charges starting at 3. Confirm values against the docs before changing balance.

## Important design boundaries

The intended resource loop is:

```text
收获灵植
→ 获得可出售的灵材/农产品
→ 贩卖获得灵石
→ 购买丹药
→ 丹药转化为修为
→ 境界突破并解锁系统
```

Resource responsibilities in the target design are:

- Harvesting produces crop goods/materials; it does **not** directly grant cultivation.
- Selling harvested goods grants spirit stones.
- Spirit stones are spent on pills and facilities; pills are the main direct source of cultivation in this slice.
- Qi pays for spells.
- Knowledge points pay for cross-reincarnation permanent upgrades.
- `灵雨诀` only accelerates growth; it must not remove insect events or grant cultivation directly.
- `庚金剑诀` only drives away active `噬金虫` events and grants insect corpses; it must not accelerate growth.
- Guardian arrays provide upgradeable tolerance against early insect attacks; they are not replaced by the sword spell.
- Seasonal and random-event multipliers belong in centralized harvest/sale/pill calculations, not in button handlers.

The shop loop is now implemented in the prototype: harvesting adds crop inventory, the UI can sell `聚灵草` for spirit stones, spirit stones can buy `聚气丹`, and consuming the pill grants cultivation. `GameState.add_rewards()` remains as legacy implementation debt and should not be used by new harvest flows.

The design target includes offline earnings, additional crops, alchemy, automation, a fuller reincarnation/endgame flow, gamepad navigation, and Steam distribution, but those are not all implemented in the current source. Do not document them as available features unless the implementation catches up.

## Change guidance

When adding a gameplay system, prefer extending `GameState` with explicit methods/data and updating `SaveManager` for persistence, then let `main.gd` render and invoke those methods. Keep all newly persisted arrays/dictionaries length-compatible with the three current field slots and provide defaults for older JSON saves. After script or scene changes, run the headless editor validation command above; because there is no automated test suite, also perform the relevant UI smoke flow in the running scene.

The authoritative product/design references are:

- `README.md`: current implemented feature list and player controls.
- `docs/GDD-v0.1.md`: confirmed design baseline and demo acceptance criteria.
- `docs/IMPLEMENTATION-PLAN-v0.1.md`: completed prototype systems, work packages, and current timing parameters.
