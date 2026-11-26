#!/usr/bin/env python3
"""apercu_spirale.py OUTD wNNN   : image d'un enroulement (CT au milieu + encre des deux faces, moyenne des modeles)
   apercu_spirale.py OUTD --planche : planches de tous les enroulements faits (4 par image)

Encre : chaque carte (reader, argus ; sens direct et inverse) est detuilee si possible, puis ramenee en z-score sur
le papyrus ; la carte d'une face = moyenne des z-scores des modeles (comme Erwin / Jeff Chen). Blanc = encre."""
import glob
import json
import os
import sys

import numpy as np
import tifffile
from PIL import Image, ImageDraw

LARG = 2400  # largeur max d'une bande dans l'apercu


def lire(t):
    a = np.squeeze(tifffile.imread(t)).astype(np.float32)
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "outils"))
        import detuile  # outil de l'equipe (motif de tuiles periode 192)
        m = a > max(1.0, np.percentile(a, 5))
        a = np.where(a == 0, 0, detuile.corrige_2d(a, 192, m)).astype(np.float32)
    except Exception as e:  # noqa: BLE001
        print("detuile non applique :", e)
    return a


def zscore(a):
    m = a > 0
    if m.sum() < 1000:
        return np.zeros_like(a)
    mu, sd = np.median(a[m]), a[m].std() + 1e-6
    z = (a - mu) / sd
    z[~m] = 0
    return z


def en_image(a, lo=None, hi=None):
    v = a[a != 0] if (a != 0).any() else a.ravel()
    lo = np.percentile(v, 1) if lo is None else lo
    hi = np.percentile(v, 99.7) if hi is None else hi
    im = Image.fromarray((np.clip((a - lo) / max(hi - lo, 1e-6), 0, 1) * 255).astype(np.uint8))
    if im.width > LARG:
        im = im.resize((LARG, max(1, round(im.height * LARG / im.width))), Image.LANCZOS)
    return im


def un(outd, w):
    enc = os.path.join(outd, "encre")
    faces = {}
    for sens, suf in (("face A", ""), ("face B", "_reverse")):
        cartes = [zscore(lire(t)) for t in sorted(glob.glob(os.path.join(enc, f"{w}_*{suf}.tif")))
                  if (suf or not t.endswith("_reverse.tif"))]
        if cartes:
            h = min(c.shape[0] for c in cartes); l = min(c.shape[1] for c in cartes)
            faces[sens] = np.mean([c[:h, :l] for c in cartes], axis=0)
    bandes = []
    r = os.path.join(outd, "rendus", f"{w}.zarr")
    try:
        import zarr
        g = zarr.open(r, mode="r")
        arr = g["0"] if hasattr(g, "keys") and "0" in g else g
        ct = np.asarray(arr[arr.shape[0] // 2]).astype(np.float32)
        bandes.append(("CT (couche du milieu)", en_image(ct)))
    except Exception as e:  # noqa: BLE001
        print("CT non lu :", e)
    stats = {}
    for k, z in faces.items():
        bandes.append((f"encre {k} (moyenne {len(glob.glob(os.path.join(enc, w + '_*.tif'))) // 2} modeles)", en_image(z, 0, 4)))
        stats[k] = {"p99": float(np.percentile(z[z != 0], 99)) if (z != 0).any() else 0.0}
    if not bandes:
        sys.exit(f"rien a montrer pour {w}")
    H = sum(b.height + 34 for _, b in bandes) + 10; L = max(b.width for _, b in bandes)
    img = Image.new("L", (L, H), 0); d = ImageDraw.Draw(img); y = 6
    for titre, b in bandes:
        d.text((6, y), f"{w}  -  {titre}", fill=255); img.paste(b, (0, y + 24)); y += b.height + 34
    os.makedirs(os.path.join(outd, "apercus"), exist_ok=True)
    img.save(os.path.join(outd, "apercus", f"{w}.png"), optimize=True)
    json.dump(stats, open(os.path.join(outd, "apercus", f"{w}.json"), "w"), indent=1)
    print("apercu", w, stats)


def planche(outd):
    pngs = sorted(glob.glob(os.path.join(outd, "apercus", "w*.png")))
    if not pngs:
        sys.exit("aucun apercu")
    for k in range(0, len(pngs), 4):
        ims = [Image.open(p).convert("L") for p in pngs[k:k + 4]]
        ims = [i.resize((1800, max(1, round(i.height * 1800 / i.width)))) for i in ims]
        H = sum(i.height + 20 for i in ims); img = Image.new("L", (1800, H), 40); y = 0
        for i in ims:
            img.paste(i, (0, y)); y += i.height + 20
        n = k // 4 + 1
        img.save(os.path.join(outd, f"planche-spirale-{n:02d}.png"), optimize=True)
    # la premiere planche aussi sous un nom fixe
    import shutil
    shutil.copy(os.path.join(outd, "planche-spirale-01.png"), os.path.join(outd, "planche-spirale.png"))
    print(len(pngs), "enroulements ->", (len(pngs) + 3) // 4, "planches")


if __name__ == "__main__":
    if sys.argv[2] == "--planche":
        planche(sys.argv[1])
    else:
        un(sys.argv[1], sys.argv[2])
