#!/bin/bash
# Roda no Linux do WSL (root) com o disco do Kali conectado (pelo Windows: kali-acesso\aplicar-no-kali.ps1
# -Script .\aplicar-sair-facil.sh): o usuário desliga/reinicia o Kali sem senha (regra do polkit). Antes, mostra o
# que pediu senha. sudo, root e o resto continuam pedindo senha.
# Uso: bash aplicar-sair-facil.sh [pasta com 49-kali-desligar-sem-senha.rules; padrão: a pasta deste script]
#      Outro usuário: USUARIO_KALI=nome bash aplicar-sair-facil.sh
set -u
PAY=${1:-$(dirname "$(readlink -f "$0")")}
U=${USUARIO_KALI:-kali}
REGRA=49-kali-desligar-sem-senha.rules
[ -f "$PAY/$REGRA" ] || { echo "ERRO: falta $PAY/$REGRA"; exit 1; }
[[ $U =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "ERRO: nome de usuário estranho: $U"; exit 1; }
M=/mnt/kali-disco
mkdir -p "$M"
ACHOU=""
for dev in $(lsblk -lnpo NAME,TYPE | awk '$2=="part"{print $1}'); do
  findmnt -rn -S "$dev" >/dev/null 2>&1 && continue
  mount -o ro "$dev" "$M" 2>/dev/null || continue
  if grep -q '^ID=kali' "$M/etc/os-release" 2>/dev/null; then ACHOU="$dev"; umount "$M"; break; fi
  umount "$M"
done
[ -z "$ACHOU" ] && { echo "ERRO: não achei a partição do Kali"; exit 2; }
mount "$ACHOU" "$M" || exit 3
trap 'mountpoint -q "$M/proc" && umount "$M/proc"; sync; umount "$M" && echo "disco do Kali fechado"' EXIT
mount -t proc proc "$M/proc"
echo "Kali em $ACHOU: $(grep '^PRETTY_NAME=' "$M/etc/os-release" | cut -d= -f2)"
grep -q "^$U:" "$M/etc/passwd" || { echo "ERRO: o usuário '$U' não existe no Kali (use USUARIO_KALI=nome)"; exit 4; }

echo "=== pedidos de senha nos últimos 3 dias (diário do Kali) ==="
chroot "$M" journalctl -D /var/log/journal --no-pager -q -o short --since "3 days ago" 2>/dev/null \
  | grep -iE 'polkit|pkexec|authentication|login1\.(power|reboot)|screensaver|light-locker|unlock' | tail -n 30
echo "=== polkit ==="
chroot "$M" dpkg-query -W -f '${Package} ${Version}\n' polkitd 2>/dev/null
D="$M/etc/polkit-1/rules.d"
[ -d "$D" ] || { echo "ERRO: $D não existe"; exit 4; }
ls -la "$D"
sed "s/subject.user === \"kali\"/subject.user === \"$U\"/; s/usuário kali/usuário $U/g" "$PAY/$REGRA" > "$D/$REGRA.novo"
install -m 0644 -o 0 -g 0 "$D/$REGRA.novo" "$D/$REGRA" && rm -f "$D/$REGRA.novo"
echo "regra instalada para o usuário $U: $(ls -l "$D/$REGRA")"
grep -n 'subject.user' "$D/$REGRA"
echo "=== bloqueio de tela (só para saber) ==="
for p in light-locker xfce4-screensaver; do
  grep -q "^Package: $p\$" "$M/var/lib/dpkg/status" && echo "instalado: $p"
done
X="$M$(awk -F: -v u="$U" '$1==u{print $6}' "$M/etc/passwd")/.config/xfce4/xfconf/xfce-perchannel-xml"
for f in xfce4-screensaver.xml xfce4-power-manager.xml; do
  [ -f "$X/$f" ] && { echo "--- $f"; grep -iE 'lock|idle|blank|sleep' "$X/$f" | sed 's/^ *//'; }
done
echo "=== fim ==="
