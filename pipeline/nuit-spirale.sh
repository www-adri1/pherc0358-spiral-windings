#!/usr/bin/env bash
# nuit-spirale.sh : ~12 h de chasse automatique sur PHerc0358 (methode des gagnants).
#   bash /mnt/c/Users/adrie/Desktop/Vesuvius*/nuit-spirale.sh
# 1) crible la bande deja faite (z 9400-10400)
# 2) pour chaque nouvelle bande nette (atlas Scan-Quality-Map, pistes publiees a partir de z 4500) :
#    donnees -> spiral fit -> collage -> 12 tours aplatis + rendus + encre -> planche -> crible
# Une bande qui plante n'arrete pas la nuit : on passe a la suivante. Tout est reprenable.
D="/mnt/c/Users/adrie/Desktop/Vesuvius Challenge"
VC="$D/vc.sh"
J="$D/chasse/PHerc0358/nuit-spirale-log.txt"
log() { echo "[$(date '+%d/%m %H:%M')] $*" | tee -a "$J"; }
BANDES="12600:13600 5200:6200 8400:9400"   # qualite 0.67 / 0.67 / 0.59 (la 9400-10400 est deja faite)
log "===== Nuit spirale : crible bande 9400-10400 puis bandes $BANDES"
bash "$VC" spirale crible && log "crible 9400-10400 OK" || log "crible 9400-10400 ECHEC"
for b in $BANDES; do
  z0=${b%:*}; z1=${b#*:}
  log "== bande $z0-$z1 : debut"
  if bash "$VC" spirale bande "$z0" "$z1"; then
    log "== bande $z0-$z1 : chasse OK, crible..."
    bash "$VC" spirale bande "$z0" "$z1" crible && log "== bande $z0-$z1 : crible OK" || log "== bande $z0-$z1 : crible ECHEC"
  else
    log "== bande $z0-$z1 : ECHEC (voir chasse/PHerc0358/spirale_z$z0/logs), on passe a la suivante"
  fi
done
log "===== Nuit terminee. Resultats : chasse/PHerc0358/spirale*/crible/ et planche-spirale*.png"
