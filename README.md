# EndHub — multi-client build

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/loader.lua"))()
```

## Bot travel

In **Farm → Farm Movement**, select **Tween** and adjust **Tween speed** in studs/second (default 85, slider 15–250). Stored TP settings migrate to Tween; an explicitly selected Fly mode remains available. The setting covers loot, route points, merchant travel and the return after selling or respawning. By default, Tween travels in 20-stud segments with a 0.20-second pause between them. Adjust **Tween segment length** and **Pause between segments** in the same group; a pause of zero restores continuous travel. Each segment starts at the current character position. These pauses do not guarantee that the server will accept movement. Pausing, changing targets, death and unloading cancel the current tween. Route waits start after arrival, and travel time does not consume the pickup timeout.

Use this same loader in each client's AutoExecute. Restart the Roblox clients once when upgrading, especially if an old PickupSpy diagnostic was injected; existing executor hooks cannot be removed by unloading this UI.

The main window has Farm, Sell and Settings. **Settings → Open Extras window** downloads the optional tools into a second window. Boss, Mob Farm, manual movement, player tools, ESP, environment controls, extended keybinds, tuning and diagnostics live on the [extras branch](https://github.com/3213123213fefefefe/endhub/tree/extras). Close Extras through its Settings tab to stop its tools and disconnect its listeners; hiding the window keeps explicitly enabled tools running. RightShift toggles the main window; RightControl initially toggles Extras.

[Full pre-refactor backup](https://github.com/3213123213fefefefe/endhub/tree/backup-before-multi-instance-20260909).

## Account isolation

Writable files now live under `EndHub/accounts/<UserId>/<PlaceId>/default/`. Existing shared settings, keybinds and positions are read once into a missing account profile; shared originals are never overwritten. Visited-server history belongs to that profile. Different accounts no longer overwrite one config/history/log file.

For deliberately different configurations of the **same account**, set `getgenv().ENDHUB_PROFILE = "second"` before the loader in that client's AutoExecute. Keep the same value on subsequent loads.

Pickup uses the previously confirmed `InteractPromptEvent("PickupDrop", drop)` remote. Seller interaction uses the existing game remotes first. The fallback never calls OS-level `keypress`/`keyrelease`; local fallback input is withheld when that client is known to be unfocused. Background GUI entry still depends on the executor supporting the game's connected GUI signals. No script can keep running inside a Roblox process that the OS or executor has suspended.

## Preserved flow

Endure → existing slot → current server → living character/respawn delay → role checks → loot route → sale when full → resume. An entire empty route triggers a hop; matching detection also counts as activity even when pickup fails. Unknown roles keep loot paused, with automatic retries after 30–40 seconds. Failed quality hops retry after a further 60–75 seconds. No duplicate cycle or Extras context is created by repeated loads.

## Validation

`python tests/run_lua_tests.py` checks Lua syntax and runs 28 deterministic simulated-service tests. With the extras branch checked out next to this directory as `endhub-extras`, it also checks those sources and runs the 29th test for actual Extras initialization/cleanup. Tests cover profile isolation, migrations, input, saved filters, duplicate loads, route/hop decisions, role outages and respawn gates. These are not a live multi-client Roblox/executor benchmark.

Multi-client-2 also bounds external teleport failures, rejects queued bootstraps delivered to another account/source job, and reports `[EndHub Pause]` / `[EndHub Teleport]` with the account and job. A transient controller error pauses work and keeps the controller alive for a checked recovery. This does not establish that another process caused a reported pause.
