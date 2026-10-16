# Jarvis

An assistant that lives in your Mac's notch. Talk or type to it.

## Start Jarvis

1. Open **Terminal**: press **⌘ Space**, type `Terminal`, press **Return**.
2. Copy this line, paste it into Terminal, press **Return**:

   ```sh
   git clone https://github.com/refriderator/Jarvis.git ~/Jarvis && sh ~/Jarvis/"Install Jarvis.command"
   ```

3. Wait a few minutes. Jarvis opens by itself and walks you through setup.

Needs macOS 15.6 or newer.

- A window offers to install **Command Line Tools**? Click **Install**, wait, then do step 2 again.
- Asked to let *codesign* use a key? Type your Mac password and click **Always Allow**.
- Downloaded the ZIP? macOS blocks double-clicking the installer. Use step 2 instead.

Next time, open Jarvis from Applications.

## Use it

- **Click the notch** and type, or press the mic.
- From any app: **Option-Space** to talk, **Option-Shift-Space** to type, **Esc** to stop it talking.
- Try "set a timer for 10 minutes", "what's on tomorrow?", "good morning", "open Safari".
- **Settings › Features** explains everything else.

Macs without a notch get a small pill at the top of the screen instead.

## Update

```sh
cd ~/Jarvis && git pull && sh "Install Jarvis.command"
```

Your settings are kept.

## Choose an AI

Settings › Connections. A free local brain answers first; harder questions go to the cloud brain.

| Local (free, private) | Cloud |
| --- | --- |
| Apple's on-device model (macOS 26) | Claude Code (Claude Pro or Max plan) |
| A Qwen model Jarvis downloads | Codex (ChatGPT plan) |
| Any [Ollama](https://ollama.com) model | A Claude API key, or any OpenAI-compatible service |

Notion and the camera need a Claude option. Calendars come from macOS's Calendar app: add accounts in System
Settings › Internet Accounts.

## Privacy

Only questions sent to a cloud AI leave your Mac. Keys and passwords are kept in your Keychain. The conversation log
is off unless you turn it on.

## Uninstall

Quit Jarvis from its menu-bar icon, then delete Jarvis from Applications. To remove its settings too, delete
`~/Library/Application Support/Jarvis`.

## Developers

A plain Swift package, no Xcode project. [DESIGN.md](DESIGN.md) explains how it works and why.

```sh
scripts/run.sh      # debug build of build/Jarvis.app, then launch it
scripts/test.sh     # unit tests
scripts/bundle.sh   # release build of build/Jarvis.app
```

## License

MIT
