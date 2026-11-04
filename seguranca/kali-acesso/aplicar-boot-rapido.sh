#!/bin/bash
# Roda no Ubuntu do WSL (root) com o disco do Kali conectado (wsl --mount --vhd <disco> --bare):
# o GRUB do Kali para de esperar 5 s com o menu na tela e entra direto. O menu fica escondido: apertar Esc no
# primeiro segundo ainda abre ele (modo de recuperação, kernel antigo). Cópias .antes-rapido dos arquivos alterados.
# Uso: bash aplicar-boot-rapido.sh        Desfazer: voltar as cópias .antes-rapido (ou GRUB_TIMEOUT=5 e update-grub)
set -u
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
trap 'sync; umount "$M" && echo "disco do Kali fechado"' EXIT
echo "Kali em $ACHOU: $(grep '^PRETTY_NAME=' "$M/etc/os-release" | cut -d= -f2)"

G="$M/etc/default/grub"
C="$M/boot/grub/grub.cfg"
[ -f "$G" ] && [ -f "$C" ] || { echo "ERRO: falta $G ou $C"; exit 4; }
echo "--- antes"
grep -n '^GRUB_TIMEOUT' "$G"
grep -rn 'GRUB_TIMEOUT' "$M/etc/default/grub.d" 2>/dev/null
grep -n 'set timeout' "$C"
cp --update=none -p "$G" "$G.antes-rapido"
cp --update=none -p "$C" "$C.antes-rapido"

# para as próximas vezes que o Kali refizer o grub.cfg (atualização de kernel)
if grep -q '^GRUB_TIMEOUT=' "$G"; then sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$G"; else echo 'GRUB_TIMEOUT=1' >> "$G"; fi
if grep -q '^GRUB_TIMEOUT_STYLE=' "$G"; then
  sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' "$G"
else
  sed -i '/^GRUB_TIMEOUT=/a GRUB_TIMEOUT_STYLE=hidden' "$G"
fi
# e já agora, no grub.cfg de hoje (as mesmas linhas que o update-grub escreveria). Depois de um boot que falhou
# (recordfail) o menu continua aparecendo por 30 s, para dar tempo de escolher a recuperação.
FALHA=$(sed -n 's/^GRUB_RECORDFAIL_TIMEOUT=//p' "$G" | tail -n 1); FALHA=${FALHA:-30}
sed -i -E 's/^([[:space:]]*)set timeout_style=menu$/\1set timeout_style=hidden/; s/^([[:space:]]*)set timeout=[0-9]+$/\1set timeout=1/' "$C"
sed -i -E '/recordfail\}" = 1 \] ; then$/{n;s/^([[:space:]]*)set timeout=[0-9]+$/\1set timeout='"$FALHA"'/}' "$C"

echo "--- depois"
grep -n '^GRUB_TIMEOUT' "$G"
grep -n 'set timeout' "$C"
if grep -A1 'set timeout_style=hidden' "$C" | grep -q 'set timeout=1$'; then echo "boot direto: ok"
else echo "AVISO: o grub.cfg não ficou como esperado (veja as linhas acima)"; fi
grep -A1 'recordfail}" = 1' "$C" | grep -q "set timeout=$FALHA\$" && echo "depois de boot com falha: menu por $FALHA s"
