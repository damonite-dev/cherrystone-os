# Cherrystone

A small, simple OS that turns old laptops and netbooks into fast web computers. Runs from a USB stick.

**Website and downloads:** https://cherrystone.damonite.com

Cherrystone is Alpine Linux with a small custom desktop built around a web browser: a sign-in
screen, a home page with your sites, a taskbar, Settings, "Save my stuff", guest mode, Reset and
Recovery. It runs on PCs from about 2008 or newer with 1 GB of RAM, 32-bit or 64-bit.

## Build

On Linux or WSL, as root:

    sh run-build.sh x86_64 x86      # both ISOs (what gets released)
    sh run-build.sh quick           # fast 32-bit test build

The ISOs end up in `~/cherrystone-build/out`. See [src/cherrystone/README.md](src/cherrystone/README.md)
for more, including building with Docker.

## What's where

- `src/cherrystone/mkiso.sh` builds the ISO; `rootfs-config.sh`, `extras*.sh` and `features.sh` set up the system
- `src/cherrystone/ui.py` and `settings.py` are the Cherrystone screens (GTK 3)
- `src/cherrystone/badwolf-cherrystone.patch` is the browser's changes
- `src/cherrystone/site` is the website

## License

The code is under the [GNU GPL v3](LICENSE). The Cherrystone name, logo and the Stony mascot art
are not covered by the license.
