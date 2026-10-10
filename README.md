# Waterhouse

Shared save for our Valheim dedicated-server world **Waterhouse** (chunked save format,
Deep North world version). Whoever hosts runs the server from this repo; the launcher
pulls the latest save before starting and pushes after every world save, so the next
host always picks up where the last one left off.

**Only one person hosts at a time.** Stop your server (Ctrl-C) and wait for
`Pushed to GitHub.` before someone else starts theirs.

## What's in here

| Path | What it is |
| --- | --- |
| `_main.<N>.*`, `*.chunk`, `cacheMinimap*` | The world save itself. Don't edit by hand. |
| `server/waterhouse_server.ps1` | Launcher: syncs with GitHub, runs the server, commits + pushes on each save. |
| `server/start_server.example.bat` | Template for the double-click launcher. |

## Hosting setup (once per PC)

Requirements: Windows, [Git for Windows](https://git-scm.com/download/win) (includes
Git Credential Manager), the **Valheim Dedicated Server** tool from Steam, and push
access to this repo.

1. Sign in to GitHub for git:
   ```
   git credential-manager github login
   ```
2. Clone into the save folder the launcher expects (the folder name must be the world name):
   ```
   git clone https://github.com/jerryfty321-spec/Waterhouse.git "%USERPROFILE%\ValheimSaves\worlds_local\Waterhouse"
   ```
3. Copy `server\start_server.example.bat` into your `Valheim dedicated server` folder
   (Steam → Library → Valheim Dedicated Server → Manage → Browse local files), rename it,
   and replace `CHANGE_ME` with the server password. **Don't commit your copy** — this
   repo is public.
4. Keep the `-ExtraArgs` world modifiers in your `.bat` the same as the template
   (currently `-modifier deathpenalty veryeasy -modifier resources more -modifier portals casual`). They're
   stored in the world, so a host with different ones changes it for everyone.
   Valid values: `-preset normal|casual|easy|hard|hardcore|immersive|hammer`,
   `-modifier combat|deathpenalty|resources|raids|portals <value>`,
   `-setkey nobuildcost|playerevents|passivemobs|nomap` (see the Dedicated Server manual).
5. Install the server-side mods (players don't need anything). Install these from
   [Thunderstore](https://thunderstore.io/c/valheim/) into the dedicated server folder,
   with r2modman or by hand:
   - `denikson-BepInExPack_Valheim` 5.4.2351 — copy the contents of its
     `BepInExPack_Valheim` folder into the server folder
   - `ValheimModding-YamlDotNet`, `ArgusMagnus-ServersideQoL` (core, incl. its `patchers` folder)
   - `ArgusMagnus-ServersideQoL_` + `Player`, `Backpack`, `ContainerSigns`, `AutoProcess`,
     `Treesurrection`, `MultiplayerTweaks`, `AdminOptions` — each into
     `BepInEx\plugins\<package name>\`

   The mod settings are the `ArgusMagnus.ServersideQoL*.cfg` files in this repo (next to
   the world files), so every host runs the same ones. The launcher switches each host to
   them automatically (`ConfigPerWorld = true`). Edit them here; the mod reloads changes
   while the server is running.
6. Forward **UDP 2456–2458** on your router to the hosting PC so friends outside your
   network can join.

## Hosting a session

1. Double-click your `.bat`. The `[sync]` lines at the top tell you what happened:
   - `World is up to date` / `Updated local world to save #…` — fine, the server starts.
   - `DIVERGED` — someone else hosted while you also had unpushed saves. The server
     won't start until you pick which history to keep (in the repo folder).
   - `Could not reach GitHub` — you'll be asked whether to start from the local copy.
2. Wait for `Game server connected`, then join.
3. The world saves every 30 min; the launcher commits and pushes at most every 4 hours
   (`-CommitIntervalMinutes`), plus on shutdown.
4. To stop: everyone logs out, then press **Ctrl-C** in the server window and wait for
   `Pushed to GitHub.` Closing the window instead can lose everything since the last
   auto-save (whatever was saved gets committed on the next start).

## Joining

- **From the hosting PC:** Join Game → Add server → `127.0.0.1:2456`.
- **Same home network as the host:** use the host's LAN IP, e.g. `192.168.x.x:2456`.
  Most home routers can't loop back to their own public IP.
- **From anywhere else:** `<host public IP>:2456`, or search the server name in
  Join Game → Community. Needs the port forwarding above.

Client and server must be on the same Valheim version; update both in Steam if you get
an "incompatible version" error.
