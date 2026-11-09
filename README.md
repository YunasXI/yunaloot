# YunaLoot

Auto lot or auto pass every treasure pool item, once, safely. For FINAL FANTASY XI on CatsEyeXI. It runs on VanaCore and on Ashita v4.

## Install

1. Copy the `yunaloot` folder into `addons\ashita`. On VanaCore, that's `Vanacore\addons\ashita\yunaloot`.
2. In the game, type `/addon load yunaloot`.

## Commands

| Command | What it does |
|---|---|
| `/yloot lot` | Lots every item that drops, once. |
| `/yloot pass` | Passes every item that drops, once. |
| `/yloot off` | Turns it off, so you choose. |
| `/yloot` | Says which one is on. |
| `/yloot size 96` | Sets the goblin's width in pixels, from 40 to 200. |

It's always off when you log in. Only the goblin's place and size are saved.

## The goblin

A small goblin always stays on screen, so you can see at a glance what's on:

- **Gold coin eyes** (they glint): Auto lot is on.
- **Red X eyes:** Auto pass is on.
- **Grey:** off.

Click it to switch: off, then Auto lot, then Auto pass, then off again. Drag it to move it.

## What it never does

These rules make sure the server never refuses anything YunaLoot sends.

- **Never twice:** one lot or pass per item. If a lot or pass for that item already left your game, YunaLoot sends nothing. That covers one you made in the game's menu and one sent by another addon.
- **Never while knocked out.**
- **Never with a full inventory.** Auto lot waits, and lots the item once you make room, as long as it's still in the pool.
- **Never a Rare item you already have.** It looks in every bag, wardrobe and Mog House storage.
- **Never an item that only flashed through the pool.** It waits 0.8 seconds after an item lands, then reads the pool again right before sending.

## Licence

GPL-3.0. Copyright (C) 2026 Yunas.
