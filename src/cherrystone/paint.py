#!/usr/bin/env python3
# Paint: a small drawing app. Brush, line, rectangle, ellipse and text,
# a colour and a size; shapes can be filled. The eraser, undo (Ctrl+Z),
# New, Open and Save (PNG, into Pictures).
# Same flat look as the rest of Cherrystone.
import os
import time

import cairo
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

GLib.set_prgname("CherryPaint")
HOME = os.path.expanduser("~")
PICS = os.path.join(HOME, "Pictures")
COLOURS = ["#202124", "#ffffff", "#d81e3c", "#e39b16", "#f4d03f", "#2e9b4f",
           "#0f8f8a", "#2b6fd6", "#6b4bc9", "#c43e8a", "#8d5524", "#9aa0a6"]
SIZES = [("S", 3), ("M", 8), ("L", 18), ("XL", 36)]
W, H = 900, 560

CSS = b"""
window.paint { background: #ffffff; }
.tools { background: #f1f3f4; padding: 5px 10px; }
.tools button { background: transparent; background-image: none; border: none; border-radius: 0;
                box-shadow: none; padding: 4px 10px; color: #202124; min-height: 28px; }
.tools button:hover { background: #e8eaed; }
.tools button.on { background: #202124; color: #ffffff; }
.tools button.on label { color: #ffffff; }
.tools button.swatch { min-width: 22px; min-height: 22px; padding: 0; border: 2px solid #dadce0; }
.tools button.swatch.on { border-color: #d81e3c; }
.tools .sep { min-width: 1px; background: #dadce0; margin: 2px 6px; }
"""


def _theme_dark():
    try:
        return open(os.path.join(HOME, ".config/cherrystone/theme")).read().strip() == "dark"
    except OSError:
        return False


css = CSS
if _theme_dark():
    css += b"""
window.paint { background: #18181a; }
.tools { background: #26262a; }
.tools button { color: #ececef; }
.tools button:hover { background: #303035; }
.tools button.on { background: #ececef; color: #18181a; }
.tools button.on label { color: #18181a; }
.tools button.swatch { border-color: #3c3c42; }
.tools .sep { background: #3c3c42; }
"""
prov = Gtk.CssProvider()
prov.load_from_data(css)
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)


def rgb(hexc):
    return tuple(int(hexc[i:i + 2], 16) / 255.0 for i in (1, 3, 5))


class Paint(Gtk.Window):
    def __init__(self):
        super().__init__(title="Paint")
        self.get_style_context().add_class("paint")
        self.set_icon_name("applications-graphics")
        self.set_default_size(W, H + 84)
        self.connect("destroy", Gtk.main_quit)
        self.colour, self.size, self.erasing = COLOURS[0], 8, False
        self.tool, self.fill, self.start, self.preview = "brush", False, None, None
        self.undo, self.last, self.path, self.changed = [], None, None, False
        self.surface = None

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)
        # two rows, so it fits a 1024-wide netbook screen: files and tools
        # on top, colours and sizes below
        rows = []
        for _ in range(2):
            r = Gtk.Box(spacing=4)
            r.get_style_context().add_class("tools")
            box.pack_start(r, False, False, 0)
            rows.append(r)
        cur = {"row": rows[0]}

        def btn(text, cb, tip=None):
            b = Gtk.Button(label=text)
            b.set_can_focus(False)
            b.connect("clicked", cb)
            if tip:
                b.set_tooltip_text(tip)
            cur["row"].pack_start(b, False, False, 0)
            return b

        def sep():
            s = Gtk.Box()
            s.get_style_context().add_class("sep")
            cur["row"].pack_start(s, False, False, 0)

        btn("New", lambda *_: self.new())
        btn("Open", lambda *_: self.open())
        btn("Save", lambda *_: self.save())
        btn("Undo", lambda *_: self.do_undo(), "Ctrl+Z")
        sep()
        self.tool_btns = []
        for name, label_, tip in (("brush", "Brush", "B"), ("line", "Line", "L"), ("rect", "Rectangle", "R"),
                                  ("ellipse", "Ellipse", "O"), ("text", "Text", "T")):
            b = btn(label_, lambda _b, n=name: self.pick_tool(n), tip)
            self.tool_btns.append((name, b))
        self.fill_btn = btn("Fill", lambda *_: self.toggle_fill(), "Filled shapes (F)")
        sep()
        self.eraser = btn("Eraser", lambda *_: self.toggle_eraser(), "E")
        cur["row"] = rows[1]
        self.swatches = []
        for c in COLOURS:
            b = Gtk.Button()
            b.set_can_focus(False)
            b.get_style_context().add_class("swatch")
            p = Gtk.CssProvider()
            p.load_from_data(("button { background: %s; }" % c).encode())
            b.get_style_context().add_provider(p, Gtk.STYLE_PROVIDER_PRIORITY_USER + 2)
            b.connect("clicked", lambda _b, c=c: self.pick_colour(c))
            cur["row"].pack_start(b, False, False, 0)
            self.swatches.append((c, b))
        sep()
        self.size_btns = []
        for name, px in SIZES:
            b = btn(name, lambda _b, px=px: self.pick_size(px), "%d px" % px)
            self.size_btns.append((px, b))

        self.area = Gtk.DrawingArea()
        self.area.set_size_request(320, 200)
        self.area.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK |
                             Gdk.EventMask.POINTER_MOTION_MASK)
        self.area.connect("configure-event", self.on_configure)
        self.area.connect("draw", self.on_draw)
        self.area.connect("button-press-event", self.on_press)
        self.area.connect("motion-notify-event", self.on_motion)
        self.area.connect("button-release-event", self.on_release)
        box.pack_start(self.area, True, True, 0)
        self.connect("key-press-event", self.on_key)
        self.connect("delete-event", self.on_close)
        self.refresh_tools()

    # ---------------------------------------------------------- canvas
    def on_configure(self, w, e):
        a = w.get_allocation()
        new = cairo.ImageSurface(cairo.FORMAT_RGB24, max(a.width, 1), max(a.height, 1))
        cr = cairo.Context(new)
        cr.set_source_rgb(1, 1, 1)
        cr.paint()
        if self.surface:                          # keep the drawing when the window grows
            cr.set_source_surface(self.surface, 0, 0)
            cr.paint()
        self.surface = new
        return True

    def on_draw(self, w, cr):
        cr.set_source_surface(self.surface, 0, 0)
        cr.paint()
        if self.start and self.preview:            # the shape you're dragging out
            self.shape(cr, self.start, self.preview)
        return False

    def shape(self, cr, a, b):
        cr.set_source_rgb(*rgb(self.colour))
        cr.set_line_width(self.size)
        cr.set_line_cap(cairo.LINE_CAP_ROUND)
        cr.set_line_join(cairo.LINE_JOIN_ROUND)
        x0, y0 = a
        x1, y1 = b
        if self.tool == "line":
            cr.move_to(x0, y0)
            cr.line_to(x1, y1)
            cr.stroke()
            return
        x, y, w, h = min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0)
        if self.tool == "rect":
            cr.rectangle(x, y, w, h)
        else:
            if w < 1 or h < 1:
                return
            cr.save()
            cr.translate(x + w / 2, y + h / 2)
            cr.scale(w / 2, h / 2)
            cr.arc(0, 0, 1, 0, 6.2832)
            cr.restore()
        if self.fill:
            cr.fill()
        else:
            cr.stroke()

    def snapshot(self):
        s = cairo.ImageSurface(cairo.FORMAT_RGB24, self.surface.get_width(), self.surface.get_height())
        cr = cairo.Context(s)
        cr.set_source_surface(self.surface, 0, 0)
        cr.paint()
        self.undo.append(s)
        del self.undo[:-30]                        # remember the last 30 steps

    def stroke(self, x0, y0, x1, y1):
        cr = cairo.Context(self.surface)
        cr.set_source_rgb(*rgb("#ffffff" if self.erasing else self.colour))
        cr.set_line_width(self.size * (2 if self.erasing else 1))
        cr.set_line_cap(cairo.LINE_CAP_ROUND)
        cr.set_line_join(cairo.LINE_JOIN_ROUND)
        cr.move_to(x0, y0)
        cr.line_to(x1, y1)
        cr.stroke()
        pad = self.size * 2 + 2
        self.area.queue_draw_area(int(min(x0, x1) - pad), int(min(y0, y1) - pad),
                                  int(abs(x1 - x0) + pad * 2), int(abs(y1 - y0) + pad * 2))
        self.changed = True

    def on_press(self, w, e):
        if e.button != 1:
            return False
        if self.tool == "text" and not self.erasing:
            self.add_text(e.x, e.y)
            return True
        self.snapshot()
        if self.tool == "brush" or self.erasing:
            self.last = (e.x, e.y)
            self.stroke(e.x, e.y, e.x + 0.01, e.y)    # a click makes a dot
        else:
            self.start, self.preview = (e.x, e.y), (e.x, e.y)
        return True

    def on_motion(self, w, e):
        if not e.state & Gdk.ModifierType.BUTTON1_MASK:
            return True
        if self.last:
            self.stroke(self.last[0], self.last[1], e.x, e.y)
            self.last = (e.x, e.y)
        elif self.start:
            x, y = e.x, e.y
            if e.state & Gdk.ModifierType.SHIFT_MASK and self.tool in ("rect", "ellipse"):
                d = max(abs(x - self.start[0]), abs(y - self.start[1]))   # Shift: square / circle
                x = self.start[0] + (d if x >= self.start[0] else -d)
                y = self.start[1] + (d if y >= self.start[1] else -d)
            self.preview = (x, y)
            self.area.queue_draw()
        return True

    def on_release(self, w, e):
        if self.start and self.preview:
            self.shape(cairo.Context(self.surface), self.start, self.preview)
            self.changed = True
        self.last = self.start = self.preview = None
        self.area.queue_draw()
        return True

    def add_text(self, x, y):
        d = Gtk.Dialog(title="Text", transient_for=self, modal=True)
        d.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Add", Gtk.ResponseType.OK)
        d.set_default_response(Gtk.ResponseType.OK)
        e = Gtk.Entry()
        e.set_activates_default(True)
        e.set_placeholder_text("Type something")
        e.set_width_chars(30)
        box = d.get_content_area()
        box.set_border_width(12)
        box.pack_start(e, False, False, 0)
        d.show_all()
        r = d.run()
        text = e.get_text()
        d.destroy()
        if r != Gtk.ResponseType.OK or not text.strip():
            return
        self.snapshot()
        cr = cairo.Context(self.surface)
        cr.set_source_rgb(*rgb(self.colour))
        cr.select_font_face("Cantarell", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        size = 12 + self.size * 2                  # S 18, M 28, L 48, XL 84
        cr.set_font_size(size)
        cr.move_to(x, y + size * 0.8)              # the click is the top-left of the text
        cr.show_text(text)
        self.changed = True
        self.area.queue_draw()

    # ----------------------------------------------------------- tools
    def refresh_tools(self):
        for c, b in self.swatches:
            (b.get_style_context().add_class if c == self.colour and not self.erasing
             else b.get_style_context().remove_class)("on")
        for px, b in self.size_btns:
            (b.get_style_context().add_class if px == self.size else b.get_style_context().remove_class)("on")
        (self.eraser.get_style_context().add_class if self.erasing
         else self.eraser.get_style_context().remove_class)("on")
        for n, b in self.tool_btns:
            (b.get_style_context().add_class if n == self.tool and not self.erasing
             else b.get_style_context().remove_class)("on")
        (self.fill_btn.get_style_context().add_class if self.fill
         else self.fill_btn.get_style_context().remove_class)("on")
        self.fill_btn.set_sensitive(self.tool in ("rect", "ellipse"))
        cur = "crosshair" if self.tool in ("line", "rect", "ellipse") else "text" if self.tool == "text" else "default"
        win_ = self.area.get_window()
        if win_:
            win_.set_cursor(Gdk.Cursor.new_from_name(self.area.get_display(), cur))

    def pick_tool(self, n):
        self.tool, self.erasing = n, False
        self.refresh_tools()

    def toggle_fill(self):
        self.fill = not self.fill
        self.refresh_tools()

    def pick_colour(self, c):
        self.colour, self.erasing = c, False
        self.refresh_tools()

    def pick_size(self, px):
        self.size = px
        self.refresh_tools()

    def toggle_eraser(self):
        self.erasing = not self.erasing
        self.refresh_tools()

    def do_undo(self):
        if not self.undo:
            return
        old = self.undo.pop()
        cr = cairo.Context(self.surface)
        cr.set_source_rgb(1, 1, 1)
        cr.paint()
        cr.set_source_surface(old, 0, 0)
        cr.paint()
        self.area.queue_draw()

    def on_key(self, w, e):
        ctrl = e.state & Gdk.ModifierType.CONTROL_MASK
        k = Gdk.keyval_name(e.keyval) or ""
        if ctrl and k.lower() == "z":
            self.do_undo()
        elif ctrl and k.lower() == "s":
            self.save()
        elif ctrl and k.lower() == "o":
            self.open()
        elif ctrl and k.lower() == "n":
            self.new()
        elif not ctrl and k.lower() == "e":
            self.toggle_eraser()
        elif not ctrl and k.lower() in ("b", "l", "r", "o", "t"):
            self.pick_tool({"b": "brush", "l": "line", "r": "rect", "o": "ellipse", "t": "text"}[k.lower()])
        elif not ctrl and k.lower() == "f":
            self.toggle_fill()
        else:
            return False
        return True

    # ------------------------------------------------------------ files
    def ask_keep(self):
        """Something not saved: Save, Don't save, or Cancel. True = go on."""
        if not self.changed:
            return True
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                              buttons=Gtk.ButtonsType.NONE, text="Save your drawing first?")
        d.add_buttons("Don't save", Gtk.ResponseType.NO, "Cancel", Gtk.ResponseType.CANCEL,
                      "Save", Gtk.ResponseType.YES)
        r = d.run()
        d.destroy()
        if r == Gtk.ResponseType.YES:
            return self.save()
        return r == Gtk.ResponseType.NO

    def new(self):
        if not self.ask_keep():
            return
        self.snapshot()
        cr = cairo.Context(self.surface)
        cr.set_source_rgb(1, 1, 1)
        cr.paint()
        self.path, self.changed = None, False
        self.set_title("Paint")
        self.area.queue_draw()

    def chooser(self, title, action, button):
        d = Gtk.FileChooserNative.new(title, self, action, button, "Cancel")
        d.set_current_folder(PICS if os.path.isdir(PICS) else HOME)
        f = Gtk.FileFilter()
        f.set_name("Pictures")
        f.add_mime_type("image/*")
        d.add_filter(f)
        return d

    def open(self):
        if not self.ask_keep():
            return
        d = self.chooser("Open a picture", Gtk.FileChooserAction.OPEN, "Open")
        path = d.get_filename() if d.run() == Gtk.ResponseType.ACCEPT else None
        d.destroy()
        if not path:
            return
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file(path)
        except GLib.Error:
            Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK,
                              text="That isn't a picture Paint can open.").run()
            return
        self.snapshot()
        cr = cairo.Context(self.surface)
        cr.set_source_rgb(1, 1, 1)
        cr.paint()
        Gdk.cairo_set_source_pixbuf(cr, pb, 0, 0)
        cr.paint()
        self.path, self.changed = path, False
        self.set_title(os.path.basename(path) + " - Paint")
        self.area.queue_draw()

    def save(self):
        path = self.path if self.path and self.path.lower().endswith(".png") else None
        if not path:
            d = self.chooser("Save your drawing", Gtk.FileChooserAction.SAVE, "Save")
            d.set_do_overwrite_confirmation(True)
            d.set_current_name("Drawing %s.png" % time.strftime("%Y-%m-%d %H.%M"))
            path = d.get_filename() if d.run() == Gtk.ResponseType.ACCEPT else None
            d.destroy()
            if not path:
                return False
            if not path.lower().endswith(".png"):
                path += ".png"
        try:
            self.surface.write_to_png(path)
        except (OSError, cairo.Error):
            Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK,
                              text="Couldn't save it there.").run()
            return False
        self.path, self.changed = path, False
        self.set_title(os.path.basename(path) + " - Paint")
        return True

    def on_close(self, *_):
        return not self.ask_keep()                 # True keeps the window open


win = Paint()
win.show_all()
win.refresh_tools()                                # now the canvas has a window: set its cursor
Gtk.main()
