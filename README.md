# Whispo - Voice-to-Text for Linux

Local speech recognition using Whisper AI with push-to-talk support for Hyprland.

![Demo](example.gif)

## Installation

```bash
git clone https://github.com/dimapanov/whispo.git
cd whispo
./install.sh
```

## Usage

Add to your Hyprland config:
```conf
bindr = ALT, SPACE, exec, ~/whispo/whispo-control.sh release
bind = ALT, SPACE, exec, ~/whispo/whispo-control.sh push
```

Then reload: `hyprctl reload`

**Hold Alt+Space to record, release to transcribe and insert text.**

## Requirements

- Linux (Arch, Ubuntu/Debian, Fedora)
- PipeWire audio system  
- Working microphone

## License

MIT