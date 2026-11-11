# mz_queue

A simple and efficient queue system for FiveM servers with real-time priorities handling.

![](https://img.shields.io/github/downloads/m3ftwz/mz_queue/total?logo=github)
![](https://img.shields.io/github/downloads/m3ftwz/mz_queue/latest/total?logo=github)
![](https://img.shields.io/github/contributors/m3ftwz/mz_queue?logo=github)
![](https://img.shields.io/github/v/release/m3ftwz/mz_queue?logo=github)

## Documentation

### Requirements

- [oxmysql](https://github.com/overextended/oxmysql)
- [ox_lib](https://github.com/overextended/ox_lib)

No framework is required. The queue stores timed priorities in its own `queue_priority` table, which is created automatically.

### Standalone setup

Start the dependencies before the queue:

```cfg
ensure oxmysql
ensure ox_lib
ensure mz_queue
```

To give an administrator the highest queue priority, grant the `mz_queue.admin` ACE permission. For example, add this to `server.cfg`, replacing `YOUR_LICENSE_HASH` with the player's license hash:

```cfg
add_ace group.admin mz_queue.admin allow
add_principal identifier.license:YOUR_LICENSE_HASH group.admin
```

The `addpriority` and `removepriority` commands remain restricted to `group.admin` through FiveM ACE permissions and can also be run from the server console.

### Commands usage

1. **addpriority**: grant priority queue privileges to a player for a positive whole number of days, after which the privilege will expire.
```yaml
/addpriority [license] [timespan]

# Example usage
/addpriority 57963d7406028280fea46d319d76eee64485a033 7

# The command above will grant user with the given license queue privileges for 7 days
```

2. **removepriority**: remove priority queue privileges from a player.
```yaml
/removepriority [license]

# Example usage
/removepriority 57963d7406028280fea46d319d76eee64485a033

# The command above will remove queue privileges from the user with the given license
```

### Priority lists auto-refresh

The priority lists automatically refresh:
- at the beginning of every hour (e.g., 11:00, 12:00, etc.)
- everytime a priority is added or removed
- whenever an ESX user's admin group changes
- when ESX starts or stops

Changes also reorder players already waiting in the queue. Admins join before priority players, followed by regular players; arrival order is preserved within each group.

ACE admin permissions are rechecked every second while players are queued, so permission changes also update their positions.

## Download

https://github.com/m3ftwz/mz_queue/releases/latest/download/mz_queue.zip

## Optional ESX compatibility

When [ESX](https://github.com/esx-framework/esx_core) is running as `es_extended`, players with the `admin` group automatically receive the highest queue priority. Existing ESX installations keep their admin priority and live group updates without additional configuration. ACE admin permissions also work with ESX.

The integration is detected automatically and handles ESX starting, stopping, or restarting. When ESX is absent or stopped, the queue does not query its `users` table or apply ESX group events. To load ESX admin priority immediately at startup, start `es_extended` before `mz_queue`.

## Features

- Real-Time Priority Handling: Adjust player priority dynamically based on their admin role or status (eg. paying player).
- Fair and Transparent Queueing: Ensures that players are handled efficiently and in a structured manner.
- Performance Optimized: Lightweight and efficient, minimizing server load while maximizing queue management.
- Easy to Configure: Simple setup with custom commands to fit your server’s needs.
- Auto-Kick for Inactivity: Keeps the queue moving by automatically removing inactive players.

## Screenshot(s)

![First in queue example](https://github.com/user-attachments/assets/7e955a80-7a82-4d77-9cba-c52433e68467)
![Other positions example](https://github.com/user-attachments/assets/cf46ca57-31b1-49c2-8114-68dd4939a7ed)

## Development

Run the server regression tests from the repository root with Lua 5.4:

```sh
lua tests/server.lua
```

The tests simulate FiveM events, connection timing, and database responses. Live FXServer and database integration should also be checked before deployment.

## License

Licensed under the [GNU Lesser General Public License v3.0 or later](LICENSE).
