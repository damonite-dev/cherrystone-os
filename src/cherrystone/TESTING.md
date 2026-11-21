# Testing Cherrystone on real hardware

A checklist for trying Cherrystone on an old laptop (written for the Acer Aspire One ZG5: Atom
N270, 32-bit, 1 GB, Intel 945 graphics, Atheros Wi-Fi). Use the **32-bit ISO**
(`cherrystone-x86.iso`). Write it to a USB stick with balenaEtcher or Rufus.

Tick what works and note what doesn't. For anything that fails, the most useful notes are *what
you did, what you expected, and what happened*. A photo of the screen helps a lot.

## 1. Starting up (from the USB stick)
- [ ] The boot menu appears (cherry picture, "Cherrystone" and "Recovery").
- [ ] The splash screen shows while it starts.
- [ ] The sign-in screen appears. How many seconds from pressing the power button? ____
- [ ] Settings > About: "Started in" ____ seconds.
- [ ] The screen fills the whole display (1024x600), text is sharp, not stretched.

## 2. The basics
- [ ] Sign in (Enter works). The Welcome screen: Enter continues.
- [ ] Nothing opens by itself after signing in; a "New here?" note points to the Tour the first time.
- [ ] The browser icon on the shelf opens the home page.
- [ ] The shelf at the bottom: launcher button, pinned apps, clock, your picture/power.
- [ ] The Windows key opens the launcher; typing searches; Escape closes it.
- [ ] Click the clock: quick settings opens at the bottom right.

## 3. Hardware
- [ ] **Wi-Fi:** quick settings > Wi-Fi lists networks; connecting with a password works.
- [ ] **Touchpad:** moving, tap to click, scrolling (two fingers or the edge).
- [ ] **Volume keys** (Fn + arrows) change the volume and show the level bar. Sound plays.
- [ ] **Brightness keys** (Fn + arrows) change the brightness.
- [ ] **Battery:** the percentage shows on the shelf; unplugging/plugging in updates it.
- [ ] **Lid:** closing it locks and sleeps; opening it wakes up to the lock screen.
- [ ] **Power button:** shuts down (with the shutdown sound).
- [ ] **Webcam / SD card slot / USB stick:** a USB stick or SD card shows a "connected" popup and
      opens in Files.
- [ ] **Startup sound** plays when the sign-in screen appears.

## 4. The browser (the important part)
Note how long each takes to become usable, roughly.
- [ ] Wikipedia article: ____ s
- [ ] A news site: ____ s
- [ ] Gmail (sign in): ____ s, usable? ____
- [ ] YouTube: does a video play? Smoothly? At which quality? ____
- [ ] Google Docs: can you type in a document? ____
- [ ] Ctrl+T opens a new tab with the home page; Ctrl+W closes it; Alt+Left goes back.
- [ ] Spell checking underlines a misspelled word in a text box.
- [ ] Ads: a site that normally has ads shows fewer/none.
- [ ] Downloading a file puts it in Files > Downloads.
- [ ] With 3-4 tabs open, does it stay usable? Does anything close by itself?

## 5. Keeping things
- [ ] **Install to disk** (Settings > Advanced): installs; it then starts from the disk without the
      USB stick, faster than from USB. Time to sign-in: ____ s
- [ ] After installing: Wi-Fi password, wallpaper and a file in Downloads are still there after a
      restart.
- [ ] **Recovery** from the USB stick finds the installed copy; **Repair** works and keeps your
      stuff.
- [ ] **Settings > Password:** set one, restart, the sign-in screen asks for it.
- [ ] **Guest mode:** browse as guest, sign out, nothing the guest did is left.
- [ ] **Reset:** after the warning, password and ERASE, it starts fresh.

## 6. General feel
- How fast does it feel overall? (1 = painful, 5 = great) ____
- What felt slow? ____
- What was confusing? ____
- What would make you (or someone you'd give it to) want to use it? ____

## If it doesn't start
- "Cherrystone couldn't start": take a photo of the screen.
- "This computer needs more memory": the laptop has less than about 800 MB available.
  Press T to try anyway.
- A black screen after the splash: restart, press Tab at the boot menu, remove `quiet` from the
  line and press Enter, then take a photo of where it stops.
