# RenderSmith 2.0 - Region Naming and Batch Asset Delivery for REAPER

**Finds the individual sounds inside your track folders, names them from the hierarchy or the UCS standard, and renders each one to its own file in an organised output tree**

![REAPER Compatibility](https://img.shields.io/badge/REAPER-6.0%2B-orange)
![Version](https://img.shields.io/badge/Version-2.0-blue)
![Lua](https://img.shields.io/badge/Lua-5.3-blueviolet)

## Installation via ReaPack

1. In REAPER open **Extensions > ReaPack > Import repositories...**
2. Paste the following URL and click **OK**:
   ```
   https://raw.githubusercontent.com/panchuel/RenderSmith/master/index.xml
   ```
3. Go to **Extensions > ReaPack > Browse packages**, find **RenderSmith** and install it.
4. Make sure [Lokasenna_GUI v2](https://github.com/jalovatt/Lokasenna_GUI) is installed. Run its library path setter once:
   `Scripts > ReaTeam Scripts > Development > Lokasenna_GUI v2 > Library > Set Lokasenna_GUI v2 library path.lua`

### Manual installation
Copy the `RenderSmith/` folder to your REAPER Scripts directory, then load `RenderSmith.lua` via **Actions > Load ReaScript**.

---

## License and trial

RenderSmith is free for 7 days with every feature unlocked. After that it needs a license key: a one-time purchase that does not expire.

1. Press **Buy a license** on the License tab.
2. The key is emailed the moment you buy, next to the download link.
3. Paste it into the **License** tab and press **Activate**.

Activation needs the internet once. After that RenderSmith re-checks roughly every 14 days and keeps working offline in between, so a studio with no connection is never locked out.

One license covers the machines you work on yourself. Before you reinstall or move to a new machine, press **Remove the license from this computer** on the old one.

When the trial ends the window still opens, but it stays on the License tab until a key is entered. Nothing you already created is touched: regions and rendered files are yours either way.

---

## Key Features
- **NameSwitch markers**: rename regions and restart numbering partway through a folder, so one folder can hold many different sounds
- **Two selection modes**: work from selected folder tracks, or select just the items you want and RenderSmith builds regions from those alone
- **Cluster preview**: see exactly which regions you would get before creating any, drawn as coloured items on a temporary track; the *Create Regions* button also carries a live count
- **Overwrite protection**: RenderSmith asks REAPER which files it would write and warns before replacing any of them
- **Gap clustering**: one region per *sound* instead of one per folder: items separated by more than the gap threshold start a new region, so twenty gunshots in one folder become twenty files
- **Hybrid regions**: keep the regions in your project, or let them exist only for the length of the render (*Regions: Keep / Temporary*)
- **Isolated renders**: each region renders only its own tracks; folders that overlap in time no longer bleed into each other's files
- **User wildcards**: a shared `$RF[NAME]` dictionary with global and per-project scope, values that may nest other wildcards
- **Per-track overrides**: pin an audio type, output folder or gap onto a folder track, or exclude it from bulk renders; the settings travel inside the .rpp
- **Wildcard naming**: flexible token-based region naming per audio type
- **Modular audio types**: create and delete your own types (up to 8) from the tool, each with its own prefix, pattern and output path
- **Custom fields**: add per-type variables (up to 5) that become wildcards: a field `weapontype` is usable as `$weapontype` in names and paths, with its value editable on the Main tab
- **UCS 8.2 naming mode**: optional per-type [Universal Category System](https://universalcategorysystem.com) naming (`CatID_FXName_CreatorID_SourceID_UserData`) with the full 82-category / 753-CatID catalog built in
- **Direct render engine**: renders regions straight to WAV without ever opening REAPER's render window; async with in-GUI progress
- **Four built-in audio types**: SFX, Music, Dialogue, Environment with independent configs
- **Hierarchy tree view**: live preview of the selected track structure before creating regions
- **Batch render**: checklist with Select All / None / Filter by Type, renders straight to organized folders
- **Configurable base folder**: set a custom root output path or leave blank to use the project folder
- **Persistent settings**: all configuration survives project close and REAPER restart

---

## Quick Start

```
1. Select one or more parent folder tracks in REAPER
2. Pick the Audio Type (SFX / Music / Dialogue / Environment)
3. Fill in any type-specific fields (BPM, character name, etc.)
   or enable UCS naming in the Config → UCS tab and pick Category/SubCategory
4. Click Create Regions
5. Switch to the Render tab, tick the regions you want and click Render Checked
```

---

## GUI Tabs

The **Audio Type** picker and the **UCS: On / Off** switch sit in the header, visible from every tab, because both apply to whatever type is selected.

| Tab | Purpose |
|-----|---------|
| **Main** | Preview track hierarchy, create regions, edit custom field values |
| **Config → Audio Types** | Edit the selected type (name, prefix, wildcard pattern); add/remove types and custom fields |
| **Config → UCS** | Pick Category/SubCategory, set CreatorID/SourceID/UserData, live filename preview |
| **Config → Advanced** | Selection mode, gap clustering and preview, the `$RF[NAME]` wildcard dictionary, and per-track overrides |
| **Render** | Set output paths, choose render engine and bit depth, pick regions, render |
| **License** | Trial status, key activation, and removing the license from this machine |

The Render tab has two render buttons, and they take their work from different places:

| Button | Renders |
|---|---|
| **Render Checked** | The regions ticked in the list: regions that already exist. Only shown when something is ticked. |
| **Build & Render** | Whatever is selected in the arrange: it builds the regions first, renders them, then keeps or discards them per *Regions: Keep / Temporary*. |

The regions list and its buttons only appear when the project actually has regions; press **Refresh** after creating some.

---

## Render Engines

| Engine | Formats | REAPER render window |
|--------|---------|----------------------|
| **Direct (default)** | WAV: 16-bit PCM, 24-bit PCM, 32-bit float; sample rate selectable (project / 44.1k / 48k / 88.2k / 96k) | Never opens. Audio is read through per-track AudioAccessors and the file is written from Lua. Progress is shown in the Render tab and the GUI stays responsive. |
| **REAPER render** | Anything REAPER can render (MP3, FLAC, OGG...) | Uses your most recent render settings; shows REAPER's progress window. |

**How the Direct engine builds the mix**: REAPER's script API cannot tap the master output, so the engine sums every audible track that has items inside the region range. Included: media items, take FX, **each track's own FX chain**, track volume/pan, mutes, solos and the parent-folder/master volume chain. **Not included: FX on parent folder tracks or on the master, sends, and envelopes.** If your sound relies on bus processing (e.g. reverb on the parent folder), switch the Engine to *REAPER render (native)* for full fidelity.

---

## Wildcard Tokens

| Token | Expands To | Type |
|-------|-----------|------|
| `$prefix` | Type prefix (`sx`, `mx`, `dx`, `env`) | All |
| `$root` | Root folder name or project filename | All |
| `$parent` | Selected parent folder name | All |
| `$bpm` | BPM value | Music |
| `$meter` | Meter string e.g. `4-4` | Music |
| `$character` | Character name | Dialogue |
| `$questtype` | Quest type e.g. `SQ`, `MQ` | Dialogue |
| `$questname` | Quest name, falls back to `$parent` if empty | Dialogue |
| `$line` | Zero-padded line number `01`, `02 ...` | Dialogue |
| `$track` | Name of the folder track the region came from | All |
| `$tracknumber` | 1-based track number | All |
| `$folders` | Ancestor folder chain, joined with `/` (for paths) | All |
| `$number` | Cluster number, zero-padded to REAPER's `autoincrsuffix` width | All |
| `$RF[NAME]` | A user wildcard from the Config → Advanced tab | All |
| `$catid` | UCS CatID e.g. `AMBForst` | UCS |
| `$fxname` | Parent folder name in CamelCase | UCS |
| `$creatorid` | Creator ID from the Config → UCS tab | UCS |
| `$sourceid` | Source ID from the Config → UCS tab | UCS |
| `$userdata` | User data from the Config → UCS tab | UCS |

UCS tokens work in output path templates too (e.g. `{base}/$catid/`).

### Custom field tokens

Every custom field you add in **Audio Config → + Field** becomes a wildcard named after it. Example: on a new "Weapons" type, add a field `weapontype` with value `Pistol`, set the pattern to `$prefix_$root_$weapontype_$parent_` and regions come out as `wp_Weapons_Pistol_Shot_`. Field values are edited on the **Main** tab under *Custom fields*.

### Example outputs
```
SFX:          sx_Weapons_Pistol_
Music:        mx_OST_MainTheme_120_4-4_
Dialogue:     dx_merchant_SQ_tutorial_welcome_01_
Environment:  env_Ambient_Jungle_
UCS mode:     AMBForst_JungleDay_PANCH_ProjectX
```

---

## UCS Naming Mode

Flip **UCS: On** in the header and the selected type creates regions with its UCS pattern (default `$catid_$fxname_$creatorid_$sourceid`) instead of its regular wildcard.

- **Category / SubCategory** pickers cover the full UCS v8.2 list; the resulting CatID is stored per audio type.
- **CreatorID / SourceID / UserData** are shared across types and sanitized to UCS rules (CamelCase, `_` reserved as field separator).
- `$fxname` is derived from the parent folder name automatically.
- The live preview shows the exact filename before you create anything.

---

## Output Path Templates

Each audio type has its own path template. The `{base}` token resolves to the base folder set in the Render tab (or the project folder if left blank).

Default: `{base}/$prefix/$root/$parent/`

---

## Clustering

By default a selected folder produces one region spanning all of its items, which was the original behaviour. Turn **Clustering: On** in the Config → Advanced tab and RenderSmith instead walks the folder's items in time order and starts a new region whenever the silence between two items exceeds the **Gap**.

- **Gap** is in seconds, or one beat at the project tempo if you switch the unit.
- **`$number`** distinguishes the resulting regions. Put it in the type's wildcard pattern (e.g. `$prefix_$root_$parent_$number`) or every cluster gets the same name. Its zero-padding follows REAPER's own `autoincrsuffix`, so `_01`, `_02`, ...
- **Number singles** decides whether a folder that yields exactly one region still gets a number. Off by default, and the leftover separator is cleaned up.

A long item lying underneath several short ones holds the cluster open for its whole length, which is usually what you want for a tail.

### Previewing before you commit

Tuning the Gap blind is guesswork, so there are two ways to see the result first:

- The **Create Regions** button on the Main tab shows how many regions the current selection would produce: *Create Regions (12)*. It updates as you change selection or Gap.
- **Preview clusters** on the Config → Advanced tab draws them as coloured empty items on a temporary track named *RenderSmith Preview*, each labelled with the name it would get. **Clear preview** removes the track, and so does closing the script.

The preview is generated by the same function that creates the regions, so it cannot disagree with the result. The preview track is excluded from every render.

---

## Overwrite Protection

Before rendering, RenderSmith checks which output files already exist and asks for confirmation, listing the first few.

For the direct engine the path is known exactly. For the native engine it writes the settings and then reads REAPER's own `RENDER_TARGETS` rather than guessing: REAPER's output names depend on format, channel count and auto-numbering, none of which the script controls.

Toggle it with **Overwrite: Warn / Silent** on the Render tab. *Silent* restores the old behaviour of replacing files without asking.

---

## NameSwitch Markers

Without them a folder is one name, so `Shot`, `Reload` and `Empty` need three folders. Drop a marker before each run and one folder gives you `sx_Weapons_Shot_01…`, `sx_Weapons_Reload_01…`.

Select the folder track, put the edit cursor where the new section starts, and press **Add / Edit NameSwitch** on the Main tab. With a marker already selected the same button renames it.

- A marker **always cuts**, however small the gap to the previous sound.
- Everything after it takes its name: the marker name replaces the folder name, so `$parent` resolves to the section.
- **Numbering restarts at 01** for each section.
- If the marker item has a **custom colour**, the regions it names inherit it, and the cluster preview shows those colours too.
- A marker is metadata, never audio: it is skipped when clustering and never becomes a region, wherever you put it. Placing it on the folder track keeps it clear of your audio tracks.
- In item-selection mode the folder's markers still apply, so picking items inside the `Reload` section names them `Reload`.

RenderBuddy edits these by double-clicking the item, which needs JS_ReaScriptAPI to intercept REAPER's notes window. RenderSmith has no JS_API dependency, so editing goes through the button instead.

---

## Selection Modes

RenderSmith decides what to work on from what you have selected:

| You selected | What happens |
|---|---|
| Media items | Only those items are clustered, grouped by the folder each belongs to |
| Folder tracks (no items) | Every item in each folder is clustered |
| Neither | Nothing; it asks you to select something |

**Item selection wins over track selection.** That is what most people expect, but it is also the easiest thing to trip over: leaving items selected from an earlier edit silently narrows the job. If that bites you, set **Mode: Folders** on the Config → Advanced tab and item selection is ignored for good. **Mode: Auto** is the default.

Naming does not change between modes. An item on `Layer A` inside the `Weapons` folder is named from `Weapons`, exactly as in track mode; item mode changes *what* is clustered, never *how* it is named.

The preview and the region count on the *Create Regions* button follow the active mode, so you always see what the current selection would actually produce.

---

## Hybrid Regions

**Build & Render** on the Render tab skips the create-then-render dance: it builds regions from whatever you have selected (folders, or just items), renders them, and then either keeps them or throws them away depending on the **Regions: Keep / Temporary** toggle.

- **Keep**: classic RenderSmith. The regions stay in the project.
- **Temporary**: the regions exist only for the render. Nothing is left behind, including if the script is killed mid-render.

Regions are never duplicated: if one already exists with the same name and range it is reused instead of stacked on top, so pressing *Create Regions* twice is harmless. In *Temporary* mode only the regions that run actually created get deleted, and any that were already yours stay.

Each region renders in isolation: the native engine mutes everything outside the region's tracks for the duration and restores it afterwards, and the direct engine simply sums that region's tracks. Ancestors of a rendering track are never muted, so folder routing survives.

---

## User Wildcards

The Config → Advanced tab holds a dictionary of your own wildcards, used as `$RF[NAME]` in name patterns and `RF[NAME]` in path templates.

- **Two scopes.** Global entries live in your REAPER install; project entries live in the .rpp and shadow global ones of the same name.
- **Values may nest.** An entry's value can contain other wildcards, including other `$RF[...]` entries, resolved recursively (capped at 8 levels so a self-reference cannot hang).
- **Unknown names are left literal**, so a typo shows up in the result instead of silently disappearing.

These are separate from the per-type **custom fields** in Audio Config: a custom field belongs to one audio type and is edited on the Main tab, while a dictionary entry is shared across every type and pattern.

---

## Per-Track Overrides

Select a folder track and use the *Selected folder track* section of the Config → Advanced tab. Overrides are stored on the track itself, so they travel inside the project file.

| Override | Effect |
|---|---|
| **Pin type** | The folder always uses that audio type, whatever the dropdown says |
| **Exclude** | The folder is skipped by region creation and by bulk renders |
| **Clear** | Removes every override from the track |

Resolution order is **track → project → global**, so a project with no overrides behaves exactly as before.

---

## File Structure

```
RenderSmith/
├── RenderSmith.lua       # Entry point (REAPER action)
└── src/
    ├── config.lua          # Defaults, product and licensing constants
    ├── json.lua            # JSON decoder               (pure Lua, no REAPER API)
    ├── net.lua             # One async HTTP POST, via curl
    ├── license.lua         # Trial clock and key activation
    ├── audio_types.lua     # Audio type CRUD + sync
    ├── settings.lua        # ExtState load/save
    ├── track_utils.lua     # Track traversal
    ├── ucs_data.lua        # UCS v8.2 catalog          (pure Lua, no REAPER API)
    ├── ucs.lua             # UCS sanitizing & lookups  (pure Lua, no REAPER API)
    ├── cluster.lua         # Gap clustering algorithm  (pure Lua, no REAPER API)
    ├── wildcard_dict.lua   # $RF[NAME] dictionary (global + project scope)
    ├── settings_cascade.lua# Track/project/global override registry
    ├── journal.lua         # Mutation journal: undoes every temporary change
    ├── region_store.lua    # Region identity (GUID) + per-region metadata
    ├── plan.lua            # Render plan: source tracks + mute isolation
    ├── preview.lua         # Cluster preview on a temporary track
    ├── nameswitch.lua      # NameSwitch markers (item P_EXT)
    ├── wildcards.lua       # Token expansion
    ├── wav_writer.lua      # WAV file writer           (pure Lua, no REAPER API)
    ├── regions.lua         # Region creation
    ├── render_direct.lua   # Direct render engine (AudioAccessor → WAV)
    ├── render.lua          # Render queue + engine dispatch
    └── gui.lua             # Lokasenna UI
```

The modules marked *pure Lua* have no `reaper.*` dependencies, which keeps the algorithmic core unit-testable without REAPER in the loop.

---

## Troubleshooting

| Symptom | Solution |
|---------|----------|
| Script fails to open | Run the Lokasenna_GUI v2 library path setter |
| No regions created | Selected tracks must be parent folders with child tracks containing media items |
| Region name looks wrong | Check the wildcard pattern in Audio Config (or the UCS pattern in the Config → UCS tab) for the active type |
| Rendered WAV is silent | Direct engine: tracks must be unmuted, routed to master (master send on) and have items inside the region range |
| Rendered WAV missing bus FX | Direct engine doesn't apply parent-folder/master FX. Switch Engine to "REAPER render (native)" |
| Need MP3/FLAC output | Switch Engine to "REAPER render (native)" in the Render tab |
| Clustered regions all share one name | Add `$number` to the type's wildcard pattern in Audio Config |
| Preview track left behind | Press *Clear preview*; it is also removed when the script closes |
| Asked about overwriting every render | Set *Overwrite: Silent* on the Render tab |
| One folder made a single huge region | Clustering is off, or the Gap is larger than the silence between your sounds |
| Only part of a folder got regions | Items were selected, so item mode kicked in. Deselect them, or set *Mode: Folders* |
| A NameSwitch did nothing | It must sit inside the folder (its own track or a child), and before the sounds it should rename |
| A folder is ignored entirely | It may be marked *Excluded*. Check the Config → Advanced tab with that track selected |
| Region names ignore the Audio Type dropdown | The folder track has a pinned type; clear it in the Config → Advanced tab |
| Browse button slow to open | Install js_ReaScriptAPI for an instant native dialog; otherwise PowerShell loads in background (~2s) |
| "Could not reach the license server" | Activation needs the internet once. If it keeps failing, check that curl works: run `curl --version` in a terminal |
| "curl was not found" | curl ships with Windows 10 (1803+) and macOS. On Linux install it with your package manager |
| Trial ended but you have a key | Paste it on the License tab and press **Activate** |
| Moving to another computer | Press **Remove the license from this computer** on the old one, then activate on the new one |
| "The stored license record is unreadable" | Enter your key again on the License tab |

---

**Version**: 2.0 · **Author**: Daniel "Panchuel" Montoya · **Compatibility**: REAPER 6.0+ · Lokasenna_GUI v2
