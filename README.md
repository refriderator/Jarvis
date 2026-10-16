# Jarvis

A Mac assistant that lives in the notch. Talk or type; it answers out loud and in captions. It can set timers, read
and add calendar events, check Notion and open apps, and the notch holds a Today list, a Finder shelf, a system
monitor, a small web browser and Picture in Picture video.

Small questions are answered on your Mac for free; bigger ones go to Claude or another AI you choose.

## Install

Needs **macOS 15.6 or newer**. Nothing else has to be installed first.

1. Download this project (**Code › Download ZIP**) and unzip it, or `git clone` it.
2. Double-click **Install Jarvis.command**. If macOS won't open it, right-click it and choose **Open**.
3. Wait a few minutes while it builds. If asked, install Apple's free Command Line Tools, then run the installer
   again. If asked to let *codesign* use a key, enter your Mac password and choose **Always Allow**.

Jarvis opens and walks you through setup. **Settings › Features** explains everything else.

To update, get the new version and run the installer again; your settings are kept. In Terminal,
`scripts/install.sh` does the same.

| macOS | What works |
| --- | --- |
| 26 or newer | Everything |
| 15.6 to 15.x | Everything except Apple's on-device AI, and the Liquid Glass skin looks frosted |

Macs without a notch work too: Jarvis sits as a small pill at the top of the screen.

## Choosing an AI

Settings › Connections. The local brain answers first; harder questions go to the cloud brain.

| Local (free, private) | Cloud |
| --- | --- |
| Apple's on-device model (macOS 26, Apple Intelligence) | Claude Code, with your Claude subscription |
| A Qwen model Jarvis downloads for you | A Claude API key |
| Any [Ollama](https://ollama.com) model | Any OpenAI-compatible service (OpenAI, OpenRouter, Groq, LM Studio...) |

Notion and the camera need one of the Claude options.

**Calendars:** Jarvis uses the calendars in macOS's Calendar app, so any account added in System Settings ›
Internet Accounts works: iCloud, Google, Outlook/Exchange, Yahoo, CalDAV.

## Privacy

Everything stays on your Mac except questions sent to a cloud AI. Keys, the Notion token and passwords saved in the
web browser are kept in your Keychain. The conversation log is off unless you turn it on.

## Uninstall

Quit Jarvis from its menu-bar icon and delete `/Applications/Jarvis.app`. To remove everything, also delete
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
