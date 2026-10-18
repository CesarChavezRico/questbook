#!/usr/bin/env python3
"""Procedural art for QuestBook's paper look. Our own, generated from nothing: no texture, atlas or code from
Dialogue UI, Social Diary or Blizzard is used or traced (Dialogue UI's repo carries no licence, so it is
treated as all rights reserved: principles only). Pure Python, no dependencies.

    python3 dev/art/gen_kit.py            # writes Textures/paper_*.tga, hairline.tga and dev/art/preview.png

Textures are 32-bit uncompressed TGA with alpha, origin top-left (the same header as mask_rect.tga), sizes are
powers of two. The page is a nine-patch: four corners (64x64), top/bottom strips (256x64, stretched along the
page), left/right strips (64x256), and a tileable grain (256x256) for the fill. The strips' torn profile is pinned
to the same depth at both ends and at the corners, so stretching never opens a seam.
"""
import math, random, struct, zlib, os

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "..", "..", "Textures")

PAPER = (0.83, 0.70, 0.50)          # the same parchment as Style.THEMES.paper.pageLeft
C0 = 11.0                           # torn depth (px) at every joint
SS = 4                              # supersampling per axis for the alpha


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def smooth(a, b, x):
    t = clamp((x - a) / (b - a)) if b != a else 1.0
    return t * t * (3 - 2 * t)


class Periodic:
    """Smooth periodic noise on u in [0,1): a sum of sines with integer frequencies, so f(0) == f(1)."""
    def __init__(self, seed, kmax, decay):
        r = random.Random(seed)
        self.c = [(k, r.uniform(0, 2 * math.pi), decay ** k) for k in range(1, kmax + 1)]
        self.norm = sum(a for _, _, a in self.c)

    def __call__(self, u):
        return sum(a * math.sin(2 * math.pi * k * u + p) for k, p, a in self.c) / self.norm


def hashf(*xs):
    """Deterministic pseudo-random in [0,1) from integers."""
    h = 2166136261
    for x in xs:
        h = ((h ^ (int(x) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
        h ^= h >> 13
    return (h & 0xFFFF) / 65536.0


class Profile:
    """Depth of the torn edge (px) at position s in [0,1], equal to C0 at both ends."""
    def __init__(self, seed, length_px):
        self.low = Periodic(seed, 7, 0.78)
        self.mid = Periodic(seed + 1, 18, 0.88)
        self.n = length_px
        self.seed = seed
        self.l0 = self.low(0)
        self.m0 = self.mid(0)

    def depth(self, s):
        w = (self.low(s) - self.l0) * 6.5 + (self.mid(s) - self.m0) * 2.6
        # pixel-scale fibres: a hashed jitter per 1/3 px, windowed to vanish at the ends
        col = int(s * self.n * 3)
        j = (hashf(self.seed, col) - 0.5) * 1.1 * smooth(0.0, 0.03, s) * smooth(0.0, 0.03, 1 - s)
        return max(2.0, C0 + w + j)


class Img:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [(0.0, 0.0, 0.0, 0.0)] * (w * h)

    def set(self, x, y, c):
        self.px[y * self.w + x] = c

    def tga(self, path):
        out = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, self.w, self.h, 32, 0x28))
        for (r, g, b, a) in self.px:
            out += bytes((int(clamp(b) * 255 + .5), int(clamp(g) * 255 + .5), int(clamp(r) * 255 + .5), int(clamp(a) * 255 + .5)))
        open(path, "wb").write(out)

    def png(self, path, bg=(0.10, 0.09, 0.08)):
        raw = bytearray()
        for y in range(self.h):
            raw.append(0)
            for x in range(self.w):
                r, g, b, a = self.px[y * self.w + x]
                raw += bytes((int(clamp(r * a + bg[0] * (1 - a)) * 255 + .5), int(clamp(g * a + bg[1] * (1 - a)) * 255 + .5), int(clamp(b * a + bg[2] * (1 - a)) * 255 + .5)))
        def chunk(t, d):
            c = struct.pack(">I", len(d)) + t + d
            return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
        open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


# ---- paper colour: mottled, with fibres, tileable (periodic in both axes) -------------------------------------

class Grain:
    def __init__(self, size, seed):
        r = random.Random(seed)
        self.size = size
        self.waves = []
        for _ in range(26):
            kx, ky = r.randint(0, 7), r.randint(0, 7)
            if kx == 0 and ky == 0:
                continue
            self.waves.append((kx, ky, r.uniform(0, 2 * math.pi), 1.0 / (1 + kx * kx + ky * ky) ** 0.6))
        self.norm = sum(w[3] for w in self.waves)
        self.fine = seed + 7

    def value(self, x, y):
        u, v = x / self.size, y / self.size
        m = sum(a * math.sin(2 * math.pi * (kx * u + ky * v) + p) for kx, ky, p, a in self.waves) / self.norm
        # fibres: short streaks along x and y, hashed on the tile grid so they wrap
        xi, yi = int(x) % self.size, int(y) % self.size
        f = (hashf(self.fine, xi, yi) - 0.5)
        f2 = (hashf(self.fine + 1, xi // 6, yi) - 0.5)
        return m, f, f2


GR = Grain(256, 11)


def paper_color(x, y, shade=1.0):
    m, f, f2 = GR.value(x, y)
    k = 1.0 + m * 0.065 + f * 0.030 + f2 * 0.020
    return tuple(clamp(c * k * shade) for c in PAPER)


def rim(dist_px):
    """Darker, slightly browner paper right at the torn edge, fading over ~4px."""
    return 1.0 - 0.26 * (1 - smooth(0.0, 4.5, dist_px))


# ---- the pieces -------------------------------------------------------------------------------------------------

def make_edge_h(seed=101):
    """Top strip, 256 x 64: torn along the top, paper below it, fading to transparent from row 28 to 56."""
    W, H = 256, 64
    prof = Profile(seed, W)
    img = Img(W, H)
    for y in range(H):
        for x in range(W):
            cov = 0.0
            dsum = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px, py = x + (sx + .5) / SS, y + (sy + .5) / SS
                    d = prof.depth(px / W)
                    if py >= d:
                        cov += 1
                    dsum += py - d
            cov /= SS * SS
            dist = dsum / (SS * SS)
            fade = 1.0 - smooth(32, 60, y)
            r, g, b = paper_color(x, y, rim(max(0.0, dist)))
            img.set(x, y, (r, g, b, cov * fade))
    return img


def transpose(img):
    out = Img(img.h, img.w)
    for y in range(img.h):
        for x in range(img.w):
            out.set(y, x, img.px[y * img.w + x])
    return out


def make_corner(seed_h=101, seed_v=202):
    """Top-left corner, 64 x 64: a rounded, torn corner that joins the top strip at x=64 and the left strip at y=64."""
    S = 64
    ph, pv = Profile(seed_h, 256), Profile(seed_v, 256)
    R = 34.0
    img = Img(S, S)
    for y in range(S):
        for x in range(S):
            cov, dsum = 0.0, 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px, py = x + (sx + .5) / SS, y + (sy + .5) / SS
                    # the straight parts follow the strips' own profile (continuing it past the joint)
                    top = ph.depth(0.0) + (ph.depth((px - S) / 256 % 1.0) - C0) * smooth(R, S, px) if px > R else None
                    left = pv.depth(0.0) + (pv.depth((py - S) / 256 % 1.0) - C0) * smooth(R, S, py) if py > R else None
                    if px >= R and py >= R:
                        inside = py >= top and px >= left
                        d = min(py - top, px - left)
                    elif px >= R:
                        inside = py >= top and math.hypot(R - px, 0) >= 0 and True
                        d = py - top
                        # above the arc's centre line: bounded by the arc from the left
                        ang = math.hypot(R - px, R - py)
                        inside = py >= top
                    elif py >= R:
                        inside = px >= left
                        d = px - left
                    else:
                        reff = R - C0 + (pv.depth(py / 256 * 0.5) - C0) * 0.5
                        dist = math.hypot(R - px, R - py)
                        inside = dist <= reff
                        d = reff - dist
                    if inside:
                        cov += 1
                    dsum += d
            cov /= SS * SS
            dist = dsum / (SS * SS)
            r, g, b = paper_color(x, y, rim(max(0.0, dist)))
            img.set(x, y, (r, g, b, cov))
    return img


def make_grain():
    img = Img(256, 256)
    for y in range(256):
        for x in range(256):
            r, g, b = paper_color(x, y)
            img.set(x, y, (r, g, b, 1.0))
    return img


def make_hairline():
    """256 x 8: a brush-like rule: a 2px stroke that swells slightly in the middle and tapers to nothing at both ends.
    White with alpha, so it takes the ink colour from SetVertexColor."""
    W, H = 256, 8
    img = Img(W, H)
    n = Periodic(5, 6, 0.7)
    for x in range(W):
        u = x / (W - 1)
        taper = smooth(0.0, 0.22, u) * smooth(0.0, 0.22, 1 - u)
        thick = 0.6 + 1.5 * taper + 0.18 * n(u)
        centre = 3.5 + 0.25 * n(u * 1.3)
        for y in range(H):
            cov = clamp(thick / 2 + 0.5 - abs(y + 0.5 - centre))
            img.set(x, y, (1, 1, 1, cov * (0.25 + 0.75 * taper ** 0.6)))
    return img


# ---- assemble a preview the way the addon lays the pieces out -----------------------------------------------------

def blit(dst, src, ox, oy, flipx=False, flipy=False):
    for y in range(src.h):
        for x in range(src.w):
            sx = src.w - 1 - x if flipx else x
            sy = src.h - 1 - y if flipy else y
            r, g, b, a = src.px[sy * src.w + sx]
            if a <= 0:
                continue
            X, Y = ox + x, oy + y
            if 0 <= X < dst.w and 0 <= Y < dst.h:
                R, G, B, A = dst.px[Y * dst.w + X]
                oa = a + A * (1 - a)
                if oa > 0:
                    dst.px[Y * dst.w + X] = ((r * a + R * A * (1 - a)) / oa, (g * a + G * A * (1 - a)) / oa, (b * a + B * A * (1 - a)) / oa, oa)


def stretch(src, w, h, flipx=False, flipy=False):
    out = Img(w, h)
    for y in range(h):
        for x in range(w):
            sx = min(src.w - 1, int((x + .5) * src.w / w))
            sy = min(src.h - 1, int((y + .5) * src.h / h))
            if flipx: sx = src.w - 1 - sx
            if flipy: sy = src.h - 1 - sy
            out.px[y * w + x] = src.px[sy * src.w + sx]
    return out


def preview(pieces, W=640, H=420):
    eh, ev, co, gr = pieces
    page = Img(W, H)
    inset = 24
    for y in range(inset, H - inset):
        for x in range(inset, W - inset):
            r, g, b = paper_color(x, y)
            page.set(x, y, (r, g, b, 1.0))
    blit(page, stretch(eh, W - 128, 64), 64, 0)
    blit(page, stretch(eh, W - 128, 64, flipy=True), 64, H - 64)
    blit(page, stretch(ev, 64, H - 128), 0, 64)
    blit(page, stretch(ev, 64, H - 128, flipx=True), W - 64, 64)
    blit(page, co, 0, 0); blit(page, co, W - 64, 0, flipx=True)
    blit(page, co, 0, H - 64, flipy=True); blit(page, co, W - 64, H - 64, flipx=True, flipy=True)
    return page


if __name__ == "__main__":
    eh = make_edge_h(); ev = transpose(make_edge_h(202)); co = make_corner(); gr = make_grain(); hl = make_hairline()
    eh.tga(os.path.join(TEX, "paper_edge_h.tga")); ev.tga(os.path.join(TEX, "paper_edge_v.tga"))
    co.tga(os.path.join(TEX, "paper_corner.tga")); gr.tga(os.path.join(TEX, "paper_grain.tga")); hl.tga(os.path.join(TEX, "hairline.tga"))
    pv = preview((eh, ev, co, gr))
    pv.png(os.path.join(HERE, "preview.png"), bg=(0.08, 0.07, 0.10))
    # a 3x crop of the top-left corner to judge the edge at pixel scale
    crop = Img(150, 100)
    for y in range(100):
        for x in range(150):
            crop.px[y * 150 + x] = pv.px[y * pv.w + x]
    big = stretch(crop, 150 * 4, 100 * 4)
    big.png(os.path.join(HERE, "preview_corner.png"), bg=(0.08, 0.07, 0.10))
    hl2 = Img(256, 40)
    blit(hl2, hl, 0, 16)
    for i in range(len(hl2.px)):
        r, g, b, a = hl2.px[i]
        hl2.px[i] = (0.26 * 1, 0.19 * 1, 0.13, a)
    hl2.png(os.path.join(HERE, "preview_hairline.png"), bg=(0.83, 0.70, 0.50))
    print("ok")
