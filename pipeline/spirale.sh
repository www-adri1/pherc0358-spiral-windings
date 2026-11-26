#!/usr/bin/env bash
# spirale.sh : la chasse aux lettres avec la methode des gagnants (PHerc. 343 / 306B / 211), sur PHerc0358.
#
#   bash spirale.sh            tout enchainer (reprend la ou ca s'etait arrete)
#   bash spirale.sh etat       ou on en est
#   bash spirale.sh refaire X  efface l'etape X (installation|donnees|fit|snap) pour la relancer
#
# Etapes (chacune laisse un fichier .ok, une etape deja faite est sautee) :
#   0 verification   GPU, RAM, place disque
#   1 installation   ancien fitter villa 0fb38c45 (+ patch d'Erwin), lasagna a329895, env Python, awscli, scripts gagnants
#   2 donnees        erwin_data.sh des gagnants : pistes publiees, normales lasagna, m7, CT, champ SDT, pools
#   3 fit            fit_spiral.py sur la bande Z0-Z1, sens ACW (1 enroulement = 1 tifxyz)
#   4 snap           snap_meshes.py d'Erwin : colle chaque enroulement sur la feuille predite
#   5 enroulements   pour chacun (du milieu vers l'exterieur) : aplatissement lasagna -> rendu 31 couches -> encre -> apercu
#   6 planche        toutes les bandes d'encre empilees dans une image a regarder
set -uo pipefail
DESK="/mnt/c/Users/adrie/Desktop/Vesuvius Challenge"
source "$DESK/spirale/spirale.env"
Z0_DEF=$Z0
if [ "${1:-}" = bande ]; then Z0=${2:?Z0}; Z1=${3:?Z1}; shift 3; fi
# bande par defaut (9400-10400) : noms d'origine ; autre bande : suffixe _z<Z0>
BT=""; [ "$Z0" != "$Z0_DEF" ] && BT="_z$Z0"
export PATH=$HOME/.local/bin:$PATH
[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"
OUTD="$DESK/chasse/$SCROLL/spirale$BT"; LOGD="$OUTD/logs"; ETB=$FL/etapes$BT; mkdir -p "$OUTD" "$FL/etapes" "$ETB" "$LOGD"   # journaux sur le Bureau : Claude peut les lire
LOG="$OUTD/spirale-log.txt"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
die() {
  log "ECHEC etape $CUR : $*"
  cp "$LOGD/$CUR.log" "$OUTD/ECHEC-$CUR.log" 2>/dev/null
  echo "------ fin du log $CUR ------"; tail -25 "$LOGD/$CUR.log" 2>/dev/null
  log "Log complet copie sur le Bureau : chasse/$SCROLL/spirale/ECHEC-$CUR.log"; exit 1; }
CUR=init

SHA_OLD=0fb38c45b488e192566ea83ae36369cb6db92652      # fitter utilise par Erwin et les gagnants 306B
SHA_LAS=a329895ea5e9bde78752e60dbc0a4878dd2ab909      # lasagna utilise pour l'aplatissement
PY=$FL/envs/flpy/bin/python
SP=$FL/villa_old/volume-cartographer/scripts/spiral
LAS=$FL/villa_las/lasagna
TP=$FL/third_party
DS=$FL/ds
BIN=$(ls -d "$DESK"/VC3D/*/bin | head -1)
RENDER="$BIN/vc_render_tifxyz.exe"
S3=https://vesuvius-challenge-open-data.s3.us-east-1.amazonaws.com
VOLURL=$S3/$SCROLL/volumes/${VOLUME_ID}-9.362um-1.2m-113keV-masked.zarr/
UMBURL=$S3/$SCROLL/representations/umbilicus/20250821151737-umbilicus-20260922235631.json
TAG=s${SCROLL#PHerc}$BT; OB=$FL/out$BT; DSN=$SCROLL$BT; mkdir -p "$OB"

etape() {  # etape NOM FONCTION
  CUR=$1
  local E=$ETB; case $1 in verification|installation|natif) E=$FL/etapes ;; esac
  if [ -f "$E/$1.ok" ]; then log "== $1 : deja fait"; return 0; fi
  log "== $1 : debut"; local t0=$(date +%s)
  "$2" || die "voir le log"
  touch "$E/$1.ok"; log "== $1 : OK en $(( ($(date +%s) - t0) / 60 )) min"
}

# ------------------------------------------------------------------------------------------------ 0
e_verif() {
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | tee -a "$LOG" || return 1
  local free=$(df --output=avail -BG "$HOME" | tail -1 | tr -dc 0-9)
  local ram=$(awk '/MemTotal/{print int($2/1048576)}' /proc/meminfo)
  log "disque libre (WSL) : ${free} Go ; RAM : ${ram} Go"
  [ "$free" -ge 60 ] || { log "Il faut au moins 60 Go libres"; return 1; }
  [ -x "$RENDER" ] || { log "vc_render_tifxyz.exe introuvable dans $BIN"; return 1; }
}

# ------------------------------------------------------------------------------------------------ 1
sparse_clone() {  # sparse_clone DIR SHA chemins...
  local d=$1 sha=$2; shift 2
  [ -d "$d/.git" ] || git clone -q --no-checkout --filter=blob:none https://github.com/ScrollPrize/villa.git "$d" || return 1
  (cd "$d" && git sparse-checkout init --cone && git sparse-checkout set "$@" && git checkout -q "$sha") || return 1
}
e_installation() {
  {
  command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh; source "$HOME/.local/bin/env"; }
  command -v aws >/dev/null || uv tool install -q awscli || return 1
  sparse_clone "$FL/villa_old" $SHA_OLD volume-cartographer/scripts/spiral vesuvius/src || return 1
  sparse_clone "$FL/villa_las" $SHA_LAS lasagna vesuvius/src || return 1
  # patch d'Erwin : le fitter tourne sans dossier outer_shell/
  grep -q 'flpipe: shell optional' "$SP/fit_spiral.py" || sed -i \
    's/filter_tracks_by_shell = bool(self.tracks_dbm_path) and bool(self.shell_path)$/filter_tracks_by_shell = bool(self.tracks_dbm_path) and bool(self.shell_path) and os.path.isdir(self.shell_path)  # flpipe: shell optional/' \
    "$SP/fit_spiral.py"
  grep -q 'flpipe: shell optional' "$SP/fit_spiral.py" || { echo "patch shell-optional non applique"; return 1; }
  mkdir -p "$TP"
  [ -d "$TP/pherc0306b-first-letters" ] || git clone -q --depth 1 https://github.com/SirProdigle/pherc0306b-first-letters.git "$TP/pherc0306b-first-letters" || return 1
  [ -d "$TP/pherc343-first-letters" ] || git clone -q --depth 1 https://github.com/Nieuwlaar/pherc343-first-letters.git "$TP/pherc343-first-letters" || return 1
  export UV_HTTP_TIMEOUT=600 UV_HTTP_RETRIES=10 UV_CONCURRENT_DOWNLOADS=2 UV_CONCURRENT_BUILDS=1 CMAKE_BUILD_PARALLEL_LEVEL=2
  [ -x "$PY" ] || uv venv -q -p 3.14 "$FL/envs/flpy" || return 1
  "$PY" -c "import torch" 2>/dev/null || uv pip install -q -p "$PY" 'torch>=2.11,<2.13' --index-url https://download.pytorch.org/whl/cu128 || return 1
  (cd "$SP" && uv pip install -q -p "$PY" -e .) || return 1
  uv pip install -q -p "$PY" pillow scikit-image tensorstore imagecodecs requests pynrrd numcodecs timm safetensors fsspec aiohttp || return 1
  # arborescence attendue par les scripts des gagnants (chemins codes en dur)
  local W=$FL/w; mkdir -p "$W/fl" "$W/envs"
  cp "$TP/pherc0306b-first-letters/discovery/fl/scrolls.json" "$TP/pherc0306b-first-letters/discovery/fl/aws_fast.cfg" "$W/fl/"
  ln -sfn "$TP/pherc0306b-first-letters/discovery/x_recipe_erwin" "$W/x_recipe_erwin"
  ln -sfn "$FL/envs/flpy" "$W/envs/vcpy"
  sed "s#^W=/home/liam/projects/vesuvius-work;#W=$W;#" "$W/x_recipe_erwin/remote/erwin_data.sh" > "$FL/erwin_data_local.sh"
  grep -q "^W=$W;" "$FL/erwin_data_local.sh" || { echo "adaptation erwin_data.sh ratee"; return 1; }
  (cd "$SP" && "$PY" -c "import torch, fit_spiral; print('fitter ok, torch', torch.__version__, 'cuda', torch.cuda.is_available())") || return 1
  (cd "$LAS" && PYTHONPATH=$FL/villa_las/vesuvius/src:$LAS "$PY" fit.py --help >/dev/null && echo "lasagna ok") || return 1
  } > "$LOGD/installation.log" 2>&1
}

# ------------------------------------------------------------------------------------------------ 1b
# Les 3 modules C++ que l'ancien fitter exige (meme build que les gagnants : x_recipe_erwin/native)
e_natif() {
  {
  sparse_clone "$FL/villa_old" $SHA_OLD volume-cartographer/scripts/spiral vesuvius/src volume-cartographer/python/vc || return 1
  local N=$FL/native; mkdir -p "$N/src" "$FL/native_pkg/vc"
  cp "$FL/villa_old/volume-cartographer/python/vc/"{track_crossings,track_store,spiral_sampling}.cpp "$N/src/" || return 1
  cp "$TP/pherc0306b-first-letters/discovery/x_recipe_erwin/native/CMakeLists.txt" "$N/" || return 1
  echo '"""modules natifs du fitter spirale (build local)"""' > "$FL/native_pkg/vc/__init__.py"
  uv pip install -q -p "$PY" nanobind || return 1
  command -v cmake >/dev/null || { echo "cmake manquant : sudo apt install -y cmake build-essential"; return 1; }
  cmake -S "$N" -B "$N/build" -DPython_EXECUTABLE="$PY" -DPKG_OUT="$FL/native_pkg" || return 1
  cmake --build "$N/build" -j 4 || return 1
  PYTHONPATH=$FL/native_pkg "$PY" -c "import vc.track_crossings, vc.track_store, vc.spiral_sampling; print('natif ok')" || return 1
  } > "$LOGD/natif.log" 2>&1
}

# ------------------------------------------------------------------------------------------------ 2
e_donnees() {
  mkdir -p "$DS"
  curl -fsSL "$UMBURL" -o "$FL/umbilicus_$SCROLL.json" || return 1
  PATH=$FL/envs/flpy/bin:$PATH DSROOT=$DS SPIRAL_DIR=$SP SPIRAL_PY=$PY SDT_WORKERS=$SDT_WORKERS \
    DSNAME=$DSN bash "$FL/erwin_data_local.sh" "$SCROLL" "$Z0" "$Z1" "$SENSE" "$FL/umbilicus_$SCROLL.json" > "$LOGD/donnees.log" 2>&1
  grep -q DATA_OK "$LOGD/donnees.log"
}

# ------------------------------------------------------------------------------------------------ 3
run_of() { ls -d "$FL"/fits/*_$1 2>/dev/null | head -1; }
fit_band() {  # fit_band Z0 Z1
  rm -rf "$FL"/fits/*_$TAG
  (cd "$SP" && env PYTHONPATH=$FL/native_pkg PYTHONUNBUFFERED=1 WANDB_MODE=disabled PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
     FIT_SPIRAL_OUT_DIR=$FL/fits FIT_SPIRAL_RUN_TAG=$TAG \
     FIT_SPIRAL_CONFIG_OVERRIDES="{\"z_begin\": $1, \"z_end\": $2, \"input_disable_patches\": true, \"loss_weight_shell_outer\": 0, \"loss_weight_shell_patch_radius\": 0, \"dense_spacing_mode\": \"phase\", \"optimizer_num_training_steps\": $STEPS}" \
     "$PY" fit_spiral.py --dataset "$DS/$DSN" --cache "$FL/cache") >> "$LOGD/fit.log" 2>&1
  [ -f "$(run_of $TAG)/checkpoint_fitted.ckpt" ]
}
vraie_dbm() {  # le script des gagnants ne pose qu'un .dbm factice ; l'ancien fitter lit le vrai : on le telecharge (~6 Go)
  local T=$DS/$DSN/tracks P=${SCROLL}_${VOLUME_ID}_surface_m7_L0_th0.2
  [ -f "$T/.dbm_complete" ] && return 0
  local U=https://dl.ash2txt.org/datasets/spiral_datasets/$SCROLL/$VOLUME_ID/tracks/$P.dbm
  local want=$(curl -sI "$U" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}')
  log "   telechargement du vrai fichier de pistes ($((want / 1073741824)) Go)"
  for t in 1 2 3 4 5 6 7 8; do
    [ -f "$T/$P.dbm.part" ] && [ "$(stat -c %s "$T/$P.dbm.part")" = "$want" ] && break
    curl -sf --retry 3 -C - -o "$T/$P.dbm.part" "$U" || sleep $((t * 5))
  done
  [ "$(stat -c %s "$T/$P.dbm.part" 2>/dev/null)" = "$want" ] || { echo "telechargement .dbm incomplet" >> "$LOGD/fit.log"; return 1; }
  local mt=$(stat -c %Y "$T/$P.dbm" 2>/dev/null)
  mv -f "$T/$P.dbm.part" "$T/$P.dbm"
  [ -n "$mt" ] && touch -d "@$mt" "$T/$P.dbm"   # garde la date attendue par la signature du .vctracks
  touch "$T/.dbm_complete"
}
e_fit() {
  vraie_dbm || return 1
  find "$DS" -name '*.npz' -size +0 2>/dev/null | while read f; do "$PY" -c "import sys,zipfile;sys.exit(0 if zipfile.is_zipfile('$f') else 1)" || rm -f "$f"; done
  : > "$LOGD/fit.log"
  fit_band "$Z0" "$Z1" && return 0
  if grep -qi 'out of memory' "$LOGD/fit.log"; then   # 16 Go de VRAM : on retente sur une bande plus courte
    local c=$(( (Z0 + Z1) / 2 )); log "   memoire GPU insuffisante : nouvel essai sur z $((c-350))-$((c+350))"
    echo "Z0=$((c-350)); Z1=$((c+350))" > "$OB/bande_reduite.env"
    fit_band $((c - 350)) $((c + 350))
  else return 1; fi
}

# ------------------------------------------------------------------------------------------------ 4
e_snap() {
  [ -f "$OB/bande_reduite.env" ] && source "$OB/bande_reduite.env"
  local run=$(run_of $TAG) O=$OB; mkdir -p "$O/fitted" "$O/snap"
  for d in "$run"/meshes/fitted_$TAG/w[0-9][0-9][0-9]_$TAG; do [ -f "$d/x.tif" ] && ln -sfn "$d" "$O/fitted/$(basename "$d" _$TAG)"; done
  ls "$O/fitted" | grep -E '^w[0-9]{3}$' | sort > "$O/windings_all.txt"
  [ -s "$O/windings_all.txt" ] || { echo "aucun enroulement produit par le fit" > "$LOGD/snap.log"; return 1; }
  # du milieu vers l'exterieur (les enroulements du milieu sont les plus propres)
  "$PY" - "$O" "$MAXW" <<'PY'
import sys; o, n = sys.argv[1], int(sys.argv[2])
ws = [l.strip() for l in open(o + '/windings_all.txt') if l.strip()]
num = sorted(int(w[1:]) for w in ws); m = num[len(num) // 2]
open(o + '/windings.txt', 'w').write('\n'.join(sorted(ws, key=lambda w: (abs(int(w[1:]) - m), w))[:n]) + '\n')
PY
  SURF_ZARR=$DS/m7_$SCROLL "$PY" "$TP/pherc343-first-letters/mesh/snap_meshes.py" "$O/fitted" "$SCROLL" "$O/snap" \
    --windings "$O/windings.txt" --z0 "$Z0" --z1 "$Z1" --level 0 --procs 4 > "$LOGD/snap.log" 2>&1 || return 1
  cp "$O/snap/snap_report.tsv" "$OUTD/snap_report.tsv" 2>/dev/null
  log "   $(wc -l < "$O/windings.txt") enroulements colles (rapport : snap_report.tsv)"
}

# ------------------------------------------------------------------------------------------------ 5
encre() {  # encre ZARR MODELE OUT.tif
  local ck
  case $2 in
    reader) ck=$HOME/models/reader-v3/reader-v3.pth ;;
    argus) ck=$HOME/models/argus-v3/argus-v3.pth ;;
    ink9) ck=$HOME/models/ink_9um/hybrid_3d2d-seed42/step-075000.pth   # modele officiel 9 um (tutoriel encre)
          [ -s "$ck" ] || { mkdir -p "$(dirname "$ck")"; curl -fsSL -o "$ck" https://huggingface.co/scrollprize/ink_9um/resolve/main/hybrid_3d2d-seed42/step-075000.pth || return 1; } ;;
    *) return 1 ;;
  esac
  (cd "$HOME/villa/vesuvius" && uv run -q --extra models --with "zarr>=3" python -m vesuvius.ink_detection.inference.infer \
     "$1" "$ck" "$3" --overlap 0.5 --blend-mode hann --batch-size 4 --direction both)
}
un_enroulement() {  # un_enroulement wNNN
  local w=$1 O=$OB; local L=$LOGD/$w.log
  [ -f "$OUTD/apercus/$w.ok" ] && return 0
  mkdir -p "$O/flat" "$OUTD/flat" "$OUTD/rendus" "$OUTD/encre" "$OUTD/apercus"
  [ -f "$O/snap/$w/x.tif" ] || { log "   $w : pas de snap, saute"; return 0; }
  local F=$O/flat/$w/tifxyz/flatten.tifxyz
  if [ ! -f "$F/x.tif" ]; then
    log "   $w : aplatissement (lasagna)"
    echo "{\"external_surfaces\": [{\"path\": \"$O/snap/$w\"}], \"voxel_size_um\": 9.362}" > "$O/flat/$w.json"
    (cd "$LAS" && PYTHONPATH=$FL/villa_las/vesuvius/src:$LAS timeout 3600 "$PY" -u fit.py configs/flatten_fast_nofilter.json \
       "$O/flat/$w.json" --out-dir "$O/flat/$w" --device cuda) >> "$L" 2>&1
    [ -f "$F/x.tif" ] || { log "   $w : aplatissement rate (log $L)"; return 0; }
  fi
  rm -rf "$OUTD/flat/$w"; cp -r "$F" "$OUTD/flat/$w"
  local R=$OUTD/rendus/$w.zarr
  if [ ! -f "$R/.done" ]; then
    log "   $w : rendu 31 couches"
    rm -rf "$R"
    timeout 3600 "$RENDER" -v "$VOLURL" -s "$(wslpath -w "$OUTD/flat/$w")" -n 31 --scale 1 -g 0 \
      --zarr-output "$(wslpath -w "$R")" --pyramid false >> "$L" 2>&1
    [ -d "$R" ] || { log "   $w : rendu rate (log $L)"; return 0; }
    touch "$R/.done"
  fi
  for m in $MODELES; do
    [ -f "$OUTD/encre/${w}_$m.tif" ] && continue
    log "   $w : encre $m (deux sens)"
    encre "$R" "$m" "$OUTD/encre/${w}_$m.tif" >> "$L" 2>&1 || log "   $w : encre $m ratee (log $L)"
  done
  "$PY" "$DESK/spirale/apercu_spirale.py" "$OUTD" "$w" >> "$L" 2>&1 || { log "   $w : apercu rate"; return 0; }
  [ -n "${GARDER_RENDUS:-}" ] || rm -rf "$R"
  touch "$OUTD/apercus/$w.ok"; log "   $w : OK -> spirale/apercus/$w.png"
}
e_enroulements() {
  local n=0
  local tot=$(wc -l < "$OB/windings.txt")
  while read -r w <&3; do [ -n "$w" ] || continue; n=$((n+1)); log "-- enroulement $w ($n/$tot)"; un_enroulement "$w" < /dev/null; done 3< "$OB/windings.txt"
}

# ------------------------------------------------------------------------------------------------ 6
e_planche() { "$PY" "$DESK/spirale/apercu_spirale.py" "$OUTD" --planche > "$LOGD/planche.log" 2>&1; }

etat() {
  echo "=== Chasse spirale $SCROLL (z $Z0-$Z1, $SENSE) -> $OUTD ==="
  for e in verification installation natif donnees fit snap enroulements planche; do
    { [ -f "$ETB/$e.ok" ] || [ -f "$FL/etapes/$e.ok" ]; } && echo "  [x] $e" || echo "  [ ] $e"
  done
  [ -f "$OB/windings.txt" ] && echo "  enroulements prevus : $(tr '\n' ' ' < "$OB/windings.txt")"
  echo "  apercus faits : $(ls "$OUTD"/apercus/*.ok 2>/dev/null | wc -l)"
  [ -f "$OUTD/planche-spirale.png" ] && echo "  planche : $OUTD/planche-spirale.png"
}

case "${1:-tout}" in
  etat) etat; exit 0 ;;
  crible) "$PY" "$DESK/spirale/crible_spirale.py" "$OUTD" "${@:2}"; exit $? ;;
  refaire) rm -f "$ETB/${2:?etape}.ok" "$FL/etapes/$2.ok"; [ "$2" = enroulements ] && rm -f "$OUTD"/apercus/*.ok; echo "etape $2 sera refaite"; exit 0 ;;
esac
log "===== Debut chasse spirale $SCROLL z $Z0-$Z1 sens $SENSE ($MAXW enroulements, $STEPS pas)"
etape verification e_verif
etape installation e_installation
etape natif e_natif
etape donnees e_donnees
etape fit e_fit
etape snap e_snap
etape enroulements e_enroulements
rm -f "$ETB/planche.ok"; etape planche e_planche
log "===== FINI. Planche : $OUTD/planche-spirale.png"
etat | tee -a "$LOG"
