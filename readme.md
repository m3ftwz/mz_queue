# mz_queue

A simple and efficient queue system for FiveM servers with real-time priorities handling.

![](https://img.shields.io/github/downloads/m3ftwz/mz_queue/total?logo=github)
![](https://img.shields.io/github/downloads/m3ftwz/mz_queue/latest/total?logo=github)
![](https://img.shields.io/github/contributors/m3ftwz/mz_queue?logo=github)
![](https://img.shields.io/github/v/release/m3ftwz/mz_queue?logo=github)

## Documentation

### Commands usage

1. **addpriority**: grant priority queue privileges to a player for a specified number of days, after which the privilege will expire.
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
- everytime a user is set or unset as an admin

## Download

https://github.com/m3ftwz/mz_queue/releases/latest/download/mz_queue.zip

## Supported frameworks

Compatibility or support for third-party resources is not guaranteed.

- [esx](https://github.com/esx-framework/esx_core)

## Features

- Real-Time Priority Handling: Adjust player priority dynamically based on their admin role or status (eg. paying player).
- Fair and Transparent Queueing: Ensures that players are handled efficiently and in a structured manner.
- Performance Optimized: Lightweight and efficient, minimizing server load while maximizing queue management.
- Easy to Configure: Simple setup with custom commands to fit your server’s needs.
- Auto-Kick for Inactivity: Keeps the queue moving by automatically removing inactive players.

## Copyright

Copyright © 2025 m3ftwz <https://github.com/m3ftwz>

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
