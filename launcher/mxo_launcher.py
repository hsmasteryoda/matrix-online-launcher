#!/usr/bin/env python3
"""The Matrix Online launcher, rebuilt from the original 2005 launcher's own skin.

Reads the window art, buttons, sounds and terminal lines out of the player's launcher.exe (nothing is shipped),
runs a quick "Full System Check" of the install, shows our world's status and starts the game.
usage: mxo_launcher.py [--extract | --install]     (--extract only rebuilds the art cache; --install = setup wizard)
"""
import json, os, re, struct, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import retro

DEST = os.path.dirname(HERE)                       # <install>/launcher/ -> <install>
GAME = os.path.join(DEST, "pfx", "drive_c", "MxO")
ART = os.path.join(HERE, "art")
CONF = retro.read_conf(os.path.join(DEST, "mxo-installer.conf"))
WORLD = CONF.get("WORLD", "Reality")
SERVER = CONF.get("SERVER", "")
VERSION = "1.2.0"                                  # this launcher's release; signed updates come from UPDATES (GitHub)
UPDATES = CONF.get("UPDATES", "hsmasteryoda/matrix-online-launcher")

# resource ids in launcher.exe (MxO 7.6005)
BMP = {"frame": 186, "splash": 185, "agent": 183, "min": 195, "min_p": 192, "close": 193, "close_p": 194,
       "tab_patch": 216, "tab_select": 215, "tab_done": 247, "lbl_blank": 254, "lbl_done": 248,
       "row_on": 224, "bar_done": 220, "bar_dl": 222,
       "play": 212, "play_hi": 246, "play_pr": 213, "play_off": 214, "quit": 231, "quit_hi": 232,
       "acct": 203, "acct_hi": 204, "acct_pr": 205, "comm": 206, "comm_hi": 207, "comm_pr": 208,
       "supp": 209, "supp_hi": 210, "supp_pr": 211}
WAV = {"splash": 189, "click": 142, "hover": 146, "done": 243}
STR = {"os": 102, "ssh": 103, "check": 131, "scan": 132, "uptodate": 163, "access": 154, "select": 155,
       "name": 148, "status": 185, "load": 136, "open": 135, "down": 138}


def extract():
    exe = os.path.join(GAME, "launcher.exe")
    res = retro.pe_resources(exe)
    os.makedirs(ART, exist_ok=True)
    for name, rid in BMP.items():
        retro.save_png(os.path.join(ART, name + ".png"), *retro.pe_bitmap(res, rid))
    for name, rid in WAV.items():
        with open(os.path.join(ART, name + ".wav"), "wb") as f:
            f.write(res[("WAVE", rid)])
    ico = retro.pe_best_icon(res)
    if isinstance(ico, bytes):
        open(os.path.join(ART, "icon.png"), "wb").write(ico)
    elif ico:
        retro.save_png(os.path.join(ART, "icon.png"), *ico)
    strings = {}
    for (t, block), d in res.items():
        if t != 6:
            continue
        p = 0
        for i in range(16):
            n, = struct.unpack_from("<H", d, p); p += 2
            strings[(block - 1) * 16 + i] = d[p:p + 2 * n].decode("utf-16-le"); p += 2 * n
    with open(os.path.join(ART, "strings.json"), "w") as f:
        json.dump({k: strings.get(v, "") for k, v in STR.items()}, f)


def art(name):
    return os.path.join(ART, name + ".png")


def sound(name):
    p = os.path.join(ART, name + ".wav")
    for player in ("paplay", "pw-play", "aplay"):
        if os.path.exists(p) and any(os.access(os.path.join(d, player), os.X_OK) for d in os.environ.get("PATH", "").split(":")):
            retro.detach([player, p] + (["-q"] if player == "aplay" else []))
            return


def read_display(path=None):
    """(width, height, mode) from useropts.cfg, falling back to autoexec.cfg's defaults (1024 x 768, fullscreen)."""
    v = {}
    for f in ("autoexec.cfg", "useropts.cfg") if path is None else (path,):
        try:
            for line in open(path or os.path.join(GAME, f), encoding="latin-1"):
                m = re.match(r"\s*(ScreenWidth|ScreenHeight|Windowed)\s*=\s*(\d+)", line, re.I)
                if m:
                    v[m.group(1).lower()] = int(m.group(2))
        except OSError:
            pass
    return v.get("screenwidth", 1024), v.get("screenheight", 768), "windowed" if v.get("windowed") else "fullscreen"


def write_display(w, h, mode, path=None):
    """Set ScreenWidth / ScreenHeight / Windowed in useropts.cfg (it overrides autoexec.cfg), keeping the other lines."""
    path = path or os.path.join(GAME, "useropts.cfg")
    want = {"screenwidth": ("ScreenWidth", w), "screenheight": ("ScreenHeight", h), "windowed": ("Windowed", int(mode == "windowed"))}
    try:
        lines = open(path, encoding="latin-1").read().splitlines()
    except OSError:
        lines = []
    out = []
    for line in lines:
        m = re.match(r"\s*(\w+)\s*=", line)
        if not (m and m.group(1).lower() in want):
            out.append(line)
    out += ["%s = %d" % want[k] for k in ("screenwidth", "screenheight", "windowed")]
    open(path, "w", encoding="latin-1").write("\n".join(out) + "\n")


def status():
    """(world up?, players online or None) from the auth port and the server's LAN status feed."""
    up = retro.tcp_up(SERVER, 11000) if SERVER else False
    players = None
    try:
        d = json.load(urllib.request.urlopen("http://%s:8096/status.json" % SERVER, timeout=2))["mxo"]
        players = d.get("players"); up = up or d.get("up")
    except Exception:
        pass
    return up, players


class Launcher:
    PANEL = (14, 50, 486, 280)      # the dark screen inside the frame
    GREEN = "#38e848"

    def __init__(self):
        self.s = retro.Skin("The Matrix Online", art("splash"), art("icon"))
        self.S = json.load(open(os.path.join(ART, "strings.json")))
        sound("splash")
        self.s.later(1600, self.build)
        self.s.run()

    def build(self):
        s = self.s
        self.frame = s.img(art("frame")); s.c.delete("all"); s.c.create_image(0, 0, image=self.frame, anchor="nw")
        s.button(440, 4, art("min"), art("min_p"), command=s.minimize)
        s.button(470, 4, art("close"), art("close_p"), command=s.root.destroy)
        self.imgs = {k: s.img(art(k)) for k in ("tab_patch", "tab_select", "tab_done", "lbl_blank", "lbl_done", "row_on", "bar_done", "bar_dl")}
        self.tab = s.c.create_image(22 * s.s, 13 * s.s, image=self.imgs["tab_patch"], anchor="nw")
        self.lbl = s.c.create_image(327 * s.s, 296 * s.s, image=self.imgs["lbl_blank"], anchor="nw")
        s.c.create_image(9 * s.s, 307 * s.s, image=self.imgs["row_on"], anchor="nw")
        self.bars = [s.c.create_image(75 * s.s, y * s.s, image=self.imgs["bar_done"], anchor="nw") for y in (344, 360)]
        for b in self.bars:
            s.c.itemconfig(b, state="hidden")
        self.play = s.button(339, 324, art("play_off"), disabled=True)
        s.button(339, 379, art("quit"), art("quit_hi"), command=s.root.destroy)
        s.button(9, 376, art("acct"), art("acct_hi"), None, command=self.account)
        s.button(114, 376, art("comm"), art("comm_hi"), None, command=self.community)
        s.button(219, 376, art("supp"), art("supp_hi"), None, command=self.support)
        self.lines = []
        self.terminal([self.S["os"], "", self.S["ssh"], self.S["check"]], then=self.check)

    def set_tab(self, k):
        self.s.c.itemconfig(self.tab, image=self.imgs[k])

    def set_lbl(self, k):
        self.s.c.itemconfig(self.lbl, image=self.imgs[k])

    # ---- the green terminal in the panel
    def clear(self):
        self.s.c.delete("term"); self.lines = []

    def terminal(self, lines, then=None, speed=12):
        """Type lines out one character at a time like the original."""
        x0, y0, x1, y1 = self.PANEL
        if not lines:
            if then:
                then()
            return
        line, rest = lines[0], lines[1:]
        y = y0 + 4 + 14 * len(self.lines)
        if y > y1 - 14:
            self.s.c.move("term", 0, -14 * self.s.s); y -= 14
            self.s.c.delete(self.lines[0]); self.lines = self.lines[1:]     # scrolled off the top
        item = self.s.text(x0 + 4, y, "", size=10, color=self.GREEN, font="DejaVu Sans Mono", tags=("term",))
        self.lines.append(item)
        def type_(n=0):
            self.s.c.itemconfig(item, text=line[:n] + ("_" if n < len(line) else ""))
            if n < len(line):
                self.s.later(speed, lambda: type_(n + 1))
            else:
                self.s.later(60, lambda: self.terminal(rest, then, speed))
        type_()

    # ---- "Full System Check": the files the game needs, and our server settings
    def check(self):
        """First a signed launcher update (from the GitHub releases), then the file scan."""
        if not os.access(HERE, os.W_OK):
            return self.scan()
        def found(u):
            if not isinstance(u, tuple):              # no update, or no internet
                return self.scan()
            self.s.c.itemconfig(self.bars[0], image=self.imgs["bar_dl"], state="normal")
            def done(ok):
                if ok is True:
                    self.s.c.itemconfig(self.bars[1], state="normal")
                    self.terminal(["signature and checksums OK.", "restarting the launcher..."], then=lambda: self.s.later(600, retro.restart))
                else:
                    self.s.c.itemconfig(self.bars[0], state="hidden")
                    self.terminal(["update failed - keeping this version."], then=self.scan)
            self.terminal(["launcher update v%s found (you have v%s)" % (u[0], VERSION), "downloading..."],
                          then=lambda: retro.background(lambda: retro.apply_update(UPDATES, u, HERE), done, self.s.root))
        retro.background(lambda: retro.check_update(UPDATES, VERSION), found, self.s.root)

    def scan(self):
        need = ["client.dll", "launcher.exe", "MatrixPrivate.exe", "useropts.cfg", "resource"]
        bad = [f for f in need if not os.path.exists(os.path.join(GAME, f))]
        self.s.c.itemconfig(self.bars[0], state="normal")
        lines = [self.S["scan"].replace("%s", f).replace("\t", " ") for f in need]
        def after_scan():
            self.s.c.itemconfig(self.bars[1], state="normal")
            if bad:
                self.terminal(["", "MISSING: " + ", ".join(bad), "Run the installer again to repair."])
                return
            self.set_lbl("lbl_done"); sound("done")
            self.terminal(["", self.S["uptodate"], self.S["access"]], then=self.worlds)
        self.terminal(lines, then=after_scan, speed=4)

    def worlds(self):
        self.set_tab("tab_select")
        retro.background(status, self.show_world, self.s.root)

    def show_world(self, r):
        up, players = r if isinstance(r, tuple) else (False, None)
        st = self.S["open"] if up else self.S["down"]
        load = "-" if players is None else "%d online" % players
        self.terminal(["", self.S["select"], "",
                       "  %-22s %-8s %s" % (self.S["name"], self.S["status"], "Load"),
                       "  %-22s %-8s %s" % (WORLD, st, load)], then=lambda: self.ready(up))

    def link(self, text, cmd):
        """A clickable green terminal line (like the menus of the era)."""
        x0, y0, x1, y1 = self.PANEL
        y = y0 + 4 + 14 * len(self.lines)
        if y > y1 - 14:
            self.s.c.move("term", 0, -14 * self.s.s); y -= 14; self.s.c.delete(self.lines[0]); self.lines = self.lines[1:]
        item = self.s.text(x0 + 4, y, text, size=10, color="#a8ffb0", font="DejaVu Sans Mono", tags=("term", "btn"))
        self.lines.append(item)
        c = self.s.c
        c.tag_bind(item, "<Enter>", lambda e: (c.itemconfig(item, fill="#ffffff"), c.config(cursor="hand2")))
        c.tag_bind(item, "<Leave>", lambda e: (c.itemconfig(item, fill="#a8ffb0"), c.config(cursor="")))
        c.tag_bind(item, "<ButtonRelease-1>", lambda e: self.s.later(60, cmd))
        return item

    def display_line(self):
        w, h, mode = read_display()
        return "> Display: %d x %d, %s  [change]" % (w, h, mode)

    def display(self):
        sound("click")
        def save(w, h, m):
            write_display(w, h, m)
            for i in self.s.c.find_withtag("display"):
                self.s.c.itemconfig(i, text=self.display_line())
        retro.display_dialog(self.s.root, {"bg": "#020c04", "fg": "#9fdca6", "accent": self.GREEN, "btn_bg": "#0b2410",
                                           "font": "DejaVu Sans Mono"}, read_display(), save, modes=("fullscreen", "windowed"))

    def ready(self, up):
        s = self.s
        s.c.delete(self.play)
        self.play = s.button(339, 324, art("play"), art("play_hi"), art("play_pr"), command=self.launch)
        self.set_tab("tab_done")
        add = lambda: self.s.c.addtag_withtag("display", self.link(self.display_line(), self.display))
        self.terminal(["", "(the world isn't answering right now - you can still try)", ""] if not up else [""], then=add)

    # ---- buttons
    def launch(self):
        sound("click")
        retro.detach([os.path.join(DEST, "mxo.sh")], cwd=GAME)
        self.s.later(700, self.s.root.destroy)

    def account(self):
        sound("click"); self.clear()
        self.terminal(["ACCOUNTS", "",
                       "No sign-up needed. At the game's login screen type",
                       "a NEW username and password: your account is made",
                       "on the spot. Next time use the same ones.",
                       "", "Then create your character (body, face, clothes)",
                       "in the character creator and enter the city."], speed=3)

    def community(self):
        sound("click"); self.clear()
        def show(r):
            names = []
            try:
                d = json.load(urllib.request.urlopen("http://%s:8096/status.json" % SERVER, timeout=2))["mxo"]
                names = d.get("list") or []
            except Exception:
                pass
            self.terminal(["WHO IS JACKED IN (%s)" % WORLD, ""] + (["  " + n for n in names] or ["  nobody right now"]), speed=3)
        retro.background(lambda: None, show, self.s.root)

    def support(self):
        sound("click"); self.clear()
        self.terminal(["SUPPORT", "",
                       "Screen size and windowed mode: the line below.",
                       "Detail settings: 'The Matrix Online Settings'",
                       "from your menu (auto-detect tool).",
                       "Can't log in? The server may be restarting - try",
                       "again in a minute.  Install folder:", "  " + DEST, ""], speed=3,
                      then=lambda: self.s.c.addtag_withtag("display", self.link(self.display_line(), self.display)))


def install_wizard():
    """Setup wizard (run from the repo / USB folder): themed front end for install-mxo-linux.sh."""
    repo = DEST
    retro.Wizard({
        "title": "The Matrix Online", "bg": "#050a05", "fg": "#9fe89f", "accent": "#38e848", "btn_bg": "#0c1a0c",
        "dim": "#5f9f5f", "font": "DejaVu Sans Mono", "banner_h": 180,
        "banner": lambda c, w, h, s: retro.matrix_rain(c, w, h, s, "THE MATRIX ONLINE", "setup  //  world " + WORLD),
        "blurb": "Wake up. This installs The Matrix Online (about 6 GB) and connects it to our world, " + WORLD +
                 ". New players make their own account and character the first time they log in.",
        "fields": [("server", "Server", CONF.get("DNS") or SERVER, "text"),
                   ("dest", "Install into", os.path.expanduser("~/Games/mxo"), "folder"),
                   ("desktop", "Put a shortcut on the desktop", True, "check")],
        "script": os.path.join(repo, "install-mxo-linux.sh"),
        "args": lambda v: ["--yes", "--dest", os.path.expanduser(v["dest"]), "--server", v["server"]] + ([] if v["desktop"] else ["--no-desktop-icon"]),
        "launch": lambda d: [sys.executable, os.path.join(d, "launcher", "mxo_launcher.py")],
    })


if __name__ == "__main__":
    if "--install" in sys.argv:
        install_wizard(); sys.exit()
    if "--extract" in sys.argv or not os.path.exists(os.path.join(ART, "strings.json")):
        extract()
    if "--extract" not in sys.argv:
        Launcher()
