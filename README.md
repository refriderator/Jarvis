# Jarvis

An assistant that lives in your Mac's notch. Talk or type to it.

## Start Jarvis

Needs macOS 15.6 or newer. Do these in order; each time, paste the line, then press **Return** and wait for it to finish.

1. Open **Terminal**: press **⌘ Space**, type `Terminal`, press **Return**.
2. Paste this and press **Return**. It downloads Jarvis:

   ```sh
   git clone https://github.com/refriderator/Jarvis.git ~/Jarvis
   ```

3. Paste this and press **Return**. It builds and installs Jarvis (a few minutes, so be patient):

   ```sh
   sh ~/Jarvis/"Install Jarvis.command"
   ```

4. Jarvis opens by itself and walks you through setup.

Stuck?

- A window offers to install **Command Line Tools**? Click **Install**, wait for it to finish, then start again from step 2.
- Step 2 says `already exists`? You already have it. Skip to step 3.
- Asked to let *codesign* use a key? Type your Mac password and click **Always Allow**.
- Step 3 stops at `[3/4]` with `dyld` and `Symbol not found` (mentioning `swiftpm`)? Apple's Command Line Tools
  are broken, usually from an old copy left over after a macOS update. Reinstall them: paste
  `sudo rm -rf /Library/Developer/CommandLineTools` and press **Return** (type your Mac password; nothing shows
  as you type), then `xcode-select --install` and click **Install**. When it's done, do step 3 again.
- Step 3 says it needs **Swift 6.2 or newer**? Your Apple developer tools are too old. If you have Xcode, update
  it to Xcode 26 from the App Store, then paste `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
  and press **Return**. Otherwise, reinstall the Command Line Tools as in the step above. Then do step 3 again.
- Step 3 prints a long license and asks you to agree? Press **q**, paste `sudo xcodebuild -license accept`, press
  **Return** and type your Mac password. Then do step 3 again.
- Don't double-click the installer from a downloaded ZIP: macOS blocks it. Use the steps above.

Next time, open Jarvis from Applications.

## Use it

- **Click the notch** and type, or press the mic.
- From any app: **Option-Space** to talk, **Option-Shift-Space** to type, **Esc** to stop it talking.
- Try "set a timer for 10 minutes", "what's on tomorrow?", "good morning", "open Safari".
- **Settings › Features** explains everything else.

To put the notch on another display, pick it in the menu-bar menu under **Notch On**. Displays without a notch
get a bar that shows the time, the song and more (Settings › Display).

## Update

Open Terminal, then paste these one at a time, pressing **Return** after each:

```sh
cd ~/Jarvis
```

```sh
git pull
```

```sh
sh "Install Jarvis.command"
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
