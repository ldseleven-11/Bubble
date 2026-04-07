# Desktop Pet

A macOS desktop pet application that displays an animated pet on your screen. The pet walks around, responds to mouse interactions, and can be customized with your own graphics.

## Features

- Transparent window with animated pet
- Random walking behavior along the screen bottom
- Automatic edge detection and turning
- Mouse interactions:
  - Click to interact
  - Drag to pick up the pet
  - Release to drop (with gravity physics)
- Sleep mode after inactivity
- System tray menu for control

## Building

```bash
cd DesktopPet
swift build
```

## Running

```bash
swift run
```

Or after building:

```bash
.build/debug/DesktopPet
```

## Pet States

| State | Description |
|-------|-------------|
| idle | Standing still |
| walk | Walking horizontally |
| run | Running (faster walking) |
| sit | Sitting down |
| sleep | Sleeping (after 30s inactivity) |
| drag | Being dragged by mouse |
| interact | Clicked/interacted with |
| fall | Falling after being released |

## Custom Pet Graphics

Place your custom pet graphics in `Sources/DesktopPet/Resources/default/`:

```
Resources/default/
├── idle.gif      # Standing animation
├── walk.gif      # Walking animation
├── run.gif       # Running animation (optional, falls back to walk)
├── sit.gif       # Sitting animation
├── sleep.gif     # Sleeping animation
└── interact.gif  # Interaction animation
```

Supported formats:
- Animated GIF files
- Static PNG files

## Configuration

You can create a `config.json` in your pet folder:

```json
{
  "name": "My Cat",
  "frameRate": 10,
  "scale": 1.0,
  "states": {
    "idle": { "file": "idle.gif", "duration": 3 },
    "walk": { "file": "walk.gif", "speed": 50 },
    "sit": { "file": "sit.gif", "duration": 5 },
    "sleep": { "file": "sleep.gif" },
    "interact": { "file": "interact.gif", "duration": 1 }
  }
}
```

## System Requirements

- macOS 12.0 or later
- Swift 5.7 or later

## License

MIT
