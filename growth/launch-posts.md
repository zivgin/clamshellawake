# ClamshellAwake launch posts (ready to paste)

Owner: Maya. Written 2026-11-03. Ziv posts from his own accounts. Reply to every comment in the first 2 hours.
Best slot: Show HN on a weekday, 08:00-10:00 US Eastern (16:00-18:00 Dubai). r/macapps 1-2 days later.

## Show HN

**Title:** Show HN: ClamshellAwake, keep a MacBook running with the lid closed, no monitor

**URL:** https://github.com/zivgin/clamshellawake

**First comment:**

I run coding agents and long builds on my MacBook and wanted to close the lid and walk away. caffeinate and Amphetamine stop idle sleep, but closing the lid still sleeps the Mac unless an external display is attached.

ClamshellAwake is a small menu-bar app (one Swift file, MIT) that flips `pmset disablesleep` on only while you want it, with limits: only on power by default, pause below a battery level, pause when the Mac runs hot, and it always flips it back on quit or crash.

It asks for your password once to install a sudoers rule that allows exactly `pmset -a disablesleep 0|1` and nothing else, validated with visudo. After that there is a CLI too (`clamshellawake lid on`, `clamshellawake awake on 90`), so scripts and agents can keep the Mac awake while they work.

Happy to hear about edge cases, especially thermals with the lid shut.

## r/macapps

**Title:** [Free, open source] ClamshellAwake: keep your MacBook running with the lid closed, no external monitor

**Body:**

Made this for myself and cleaned it up to share. Close the lid, and your downloads, renders, builds or AI agents keep running.

- Menu-bar toggle + CLI
- Works without a display, keyboard or mouse
- Safety limits: only on power, battery floor, pause when hot, auto off on quit/crash
- Free, MIT, no account, no tracking

Site and FAQ: https://zivgin.github.io/clamshellawake/
Source: https://github.com/zivgin/clamshellawake

Feedback welcome, especially from people on Intel Macs.
