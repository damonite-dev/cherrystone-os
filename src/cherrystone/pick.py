#!/usr/bin/env python3
# Photos and Media Player, opened without a file: pick one first.
#   cherrystone-photos [FILE]   picture viewer (gpicview); no FILE: pick a picture
#   cherrystone-media [FILE]    media player (mpv); no FILE: pick a video or song
#   cherrystone-media --add     (O in the player) pick another file and play it
# Installed twice (as cherrystone-photos and cherrystone-media); the name
# says which one it is.
import json
import os
import socket
import sys

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk

GLib.set_prgname("CherryPick")
HOME = os.path.expanduser("~")
MEDIA = "media" in os.path.basename(sys.argv[0])
SOCK = "/tmp/cherrystone-mpv-%d" % os.getuid()
args = [a for a in sys.argv[1:] if not a.startswith("--")]
adding = "--add" in sys.argv[1:]


def pick():
    title = "Choose a video or song" if MEDIA else "Choose a picture"
    d = Gtk.FileChooserNative.new(title, None, Gtk.FileChooserAction.OPEN, "Open", "Cancel")
    start = os.path.join(HOME, "Videos" if MEDIA else "Pictures")
    d.set_current_folder(start if os.path.isdir(start) else HOME)
    f = Gtk.FileFilter()
    if MEDIA:
        f.set_name("Videos and music")
        for m in ("video/*", "audio/*"):
            f.add_mime_type(m)
    else:
        f.set_name("Pictures")
        f.add_mime_type("image/*")
    d.add_filter(f)
    every = Gtk.FileFilter()
    every.set_name("All files")
    every.add_pattern("*")
    d.add_filter(every)
    path = d.get_filename() if d.run() == Gtk.ResponseType.ACCEPT else None
    d.destroy()
    return path


def send_to_player(path):
    """Tell the media player that's already open to play this instead."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(SOCK)
        s.sendall((json.dumps({"command": ["loadfile", path, "replace"]}) + "\n").encode())
        s.close()
        return True
    except OSError:
        return False


path = args[0] if args else pick()
if not path:
    sys.exit(0)

if MEDIA:
    if adding and send_to_player(path):
        sys.exit(0)
    os.execvp("mpv", ["mpv", "--force-window=yes", "--keep-open=yes",
                      "--input-ipc-server=" + SOCK, "--", path])
else:
    os.execvp("gpicview", ["gpicview", path])
