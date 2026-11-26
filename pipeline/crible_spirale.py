#!/usr/bin/env python3
"""crible_spirale.py OUTD [--top 20] : passe chaque enroulement au crible en PLEINE resolution.

Recette inspiree des gagnants de PHerc. 306B (window_score : periodicite des lignes) :
- carte d'une face = moyenne des z-scores des modeles (reader, argus, ink9) ;
- fenetres carrees de 2 cm (= 4 cm2, 2136 px a 9,362 um), pas de 1 cm ;
- score de lignes : profil vertical (moyenne de chaque ligne de pixels), on cherche une periodicite
  de 3 a 8 mm (interligne du grec) dans son spectre -> part de puissance dans cette bande ;
- accord des modeles : correlation moyenne entre les modeles dans la fenetre (encre vraie = modeles d'accord) ;
- score final = lignes x accord x encre (p95 du z-score), seulement sur papyrus (>= 70 % de pixels valides).
Sorties dans OUTD/crible/ : classement.tsv, top_XX_<w>_<face>_<y>_<x>.png (1068 px, + barre de 1 cm),
planche-crible.png (les meilleures fenetres cote a cote)."""
import glob
import os
import sys

import numpy as np
import tifffile
from PIL import Image, ImageDraw

UM = 9.362
WIN = int(round(20000 / UM))       # 2 cm
STEP = WIN // 2
P_LO, P_HI = 3000 / UM, 8000 / UM  # interligne 3-8 mm en pixels


def z(a):
    m = a > 0
    if m.sum() < 1000:
        return np.zeros_like(a, dtype=np.float32), m
    v = a[m]
    return ((a - np.median(v)) / (v.std() + 1e-6)).astype(np.float32) * m, m


def score_lignes(w):
    prof = w.mean(axis=1)
    prof = prof - prof.mean()
    if not prof.any():
        return 0.0, 0.0
    sp = np.abs(np.fft.rfft(prof * np.hanning(len(prof)))) ** 2
    f = np.fft.rfftfreq(len(prof))
    bande = (f > 1 / P_HI) & (f < 1 / P_LO)
    tot = sp[1:].sum() + 1e-9
    k = np.argmax(np.where(bande, sp, 0))
    return float(sp[bande].sum() / tot), float(1 / f[k] * UM / 1000) if f[k] > 0 else 0.0


def charge(enc, w, suf):
    fs = [t for t in sorted(glob.glob(os.path.join(enc, f"{w}_*{suf}.tif"))) if suf or not t.endswith("_reverse.tif")]
    ms, valid = [], None
    for t in fs:
        zz, m = z(np.squeeze(tifffile.imread(t)).astype(np.float32))
        ms.append(zz); valid = m if valid is None else valid[:m.shape[0], :m.shape[1]] & m[:valid.shape[0], :valid.shape[1]]
    if not ms:
        return fs, None, None, None
    H = min(m.shape[0] for m in ms); L = min(m.shape[1] for m in ms)
    ms = [m[:H, :L] for m in ms]
    return fs, ms, valid[:H, :L], np.mean(ms, axis=0)


def main():
    outd = sys.argv[1]
    top = int(sys.argv[sys.argv.index("--top") + 1]) if "--top" in sys.argv else 20
    enc = os.path.join(outd, "encre")
    cri = os.path.join(outd, "crible"); os.makedirs(cri, exist_ok=True)
    ws = sorted({os.path.basename(t).split("_")[0] for t in glob.glob(os.path.join(enc, "w*_*.tif"))})
    rows = []
    for w in ws:
        for face, suf in (("A", ""), ("B", "_reverse")):
            fs, ms, valid, ens = charge(enc, w, suf)
            if ms is None:
                continue
            H, L = ens.shape
            print(f"{w} face {face}: {len(fs)} modeles, {H}x{L} px", flush=True)
            for y in range(0, max(1, H - WIN + 1), STEP):
                for x in range(0, max(1, L - WIN + 1), STEP):
                    v = valid[y:y + WIN, x:x + WIN]
                    if v.mean() < 0.7:
                        continue
                    e = ens[y:y + WIN, x:x + WIN]
                    lig, per = score_lignes(e)
                    acc = []
                    for i in range(len(ms)):
                        for j in range(i + 1, len(ms)):
                            a_, b_ = ms[i][y:y + WIN, x:x + WIN][v], ms[j][y:y + WIN, x:x + WIN][v]
                            acc.append(np.corrcoef(a_, b_)[0, 1])
                    accord = float(np.nanmean(acc)) if acc else 0.0
                    encre = float(np.percentile(e[v], 95))
                    sc = lig * max(accord, 0) * max(encre, 0)
                    rows.append((sc, w, face, y, x, lig, per, accord, encre))
    rows.sort(reverse=True)
    with open(os.path.join(cri, "classement.tsv"), "w") as fh:
        fh.write("rang\tscore\tenroulement\tface\ty\tx\tscore_lignes\tinterligne_mm\taccord_modeles\tencre_p95\n")
        for k, r in enumerate(rows, 1):
            fh.write(f"{k}\t{r[0]:.4f}\t{r[1]}\t{r[2]}\t{r[3]}\t{r[4]}\t{r[5]:.3f}\t{r[6]:.1f}\t{r[7]:.3f}\t{r[8]:.2f}\n")
    ims = []
    cache = {}
    for k, r in enumerate(rows[:top], 1):
        key = (r[1], r[2])
        if key not in cache:
            cache.clear(); cache[key] = charge(enc, r[1], "" if r[2] == "A" else "_reverse")[3]
        e = cache[key][r[3]:r[3] + WIN, r[4]:r[4] + WIN]
        im = Image.fromarray((np.clip(e / 4, 0, 1) * 255).astype(np.uint8)).resize((STEP, STEP), Image.LANCZOS).convert("L")
        d = ImageDraw.Draw(im); cm = STEP // 2   # 1 cm = moitie de la fenetre
        d.rectangle([10, STEP - 22, 10 + cm, STEP - 16], fill=255); d.text((10, STEP - 40), "1 cm", fill=255)
        d.text((6, 6), f"#{k} {r[1]} face {r[2]} y{r[3]} x{r[4]}  lignes {r[5]:.2f} ({r[6]:.1f} mm) accord {r[7]:.2f}", fill=255)
        nom = f"top_{k:02d}_{r[1]}_{r[2]}_y{r[3]}_x{r[4]}.png"; im.save(os.path.join(cri, nom)); ims.append(im)
    if ims:
        c = 4; S = STEP // 2; n = len(ims)
        pl = Image.new("L", (c * (S + 6), ((n + c - 1) // c) * (S + 6)), 30)
        for i, im in enumerate(ims):
            pl.paste(im.resize((S, S)), ((i % c) * (S + 6), (i // c) * (S + 6)))
        pl.save(os.path.join(cri, "planche-crible.png"))
    print(f"{len(rows)} fenetres notees ; top {len(ims)} dans {cri}")


if __name__ == "__main__":
    main()
