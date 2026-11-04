#!/bin/bash
# Roda no Linux do WSL (root) com o disco do Kali conectado (pelo Windows: kali-acesso\aplicar-no-kali.ps1
# -Script ..\kali-visual\aplicar-sombrio.sh -Pasta <pasta>): tema antigo "Anonymous sombrio" (substituído pela
# Máscara verde; fica aqui para quem preferir). Terminal mais escuro para o usuário e o root.
# Uso: bash aplicar-sombrio.sh <pasta com Caveira.colorscheme, bloco-kali.zsh, bloco-root.zsh e kali-anonymous.png>
#      Outro usuário: USUARIO_KALI=nome bash aplicar-sombrio.sh <pasta>
set -u
PAY=${1:?informe a pasta com os arquivos}
U=${USUARIO_KALI:-kali}
for f in Caveira.colorscheme bloco-kali.zsh bloco-root.zsh kali-anonymous.png; do
  [ -f "$PAY/$f" ] || { echo "ERRO: falta $PAY/$f"; exit 1; }
done
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
KU=$(awk -F: -v u="$U" '$1==u{print $3":"$4}' "$M/etc/passwd")
CASA=$(awk -F: -v u="$U" '$1==u{print $6}' "$M/etc/passwd")
[ -n "$KU" ] && [ -n "$CASA" ] || { echo "ERRO: o usuário '$U' não existe no Kali (use USUARIO_KALI=nome)"; exit 4; }

# cores mais escuras
for d in qtermwidget5 qtermwidget6; do
  [ -d "$M/usr/share/$d/color-schemes" ] && install -m 0644 -o 0 -g 0 "$PAY/Caveira.colorscheme" "$M/usr/share/$d/color-schemes/Caveira.colorscheme" && echo "esquema Caveira (mais escuro) em $d"
done

# usuário: troca o bloco antigo pelo novo
UZ="$M$CASA/.zshrc"
cp --update=none "$UZ" "$UZ.antes"
sed -i '/^# >>> caveira (personalização/,/^# <<< caveira <<<$/d' "$UZ"
printf '\n' >> "$UZ"; cat "$PAY/bloco-kali.zsh" >> "$UZ"
chown "$KU" "$UZ"
echo "$U: $(grep -c 'caveira' "$UZ") linha(s) com a marca caveira no .zshrc"

# root: bloco próprio, mais sombrio
RZ="$M/root/.zshrc"
[ -f "$RZ" ] && cp --update=none "$RZ" "$RZ.antes"
[ -f "$RZ" ] || { [ -f "$M/etc/skel/.zshrc" ] && cp "$M/etc/skel/.zshrc" "$RZ"; }
sed -i '/^# >>> caveira root/,/^# <<< caveira root <<<$/d' "$RZ"
printf '\n' >> "$RZ"; cat "$PAY/bloco-root.zsh" >> "$RZ"
chown 0:0 "$RZ"; chmod 0644 "$RZ"
echo "root: shell $(awk -F: '$1=="root"{print $7}' "$M/etc/passwd") | $(grep -c 'caveira root' "$RZ") linha(s) com a marca no .zshrc"

# terminal aberto como root (menu "Root Terminal"): mesmas cores e fonte
RI="$M/root/.config/qterminal.org/qterminal.ini"
mkdir -p "$(dirname "$RI")"
[ -f "$RI" ] && cp --update=none "$RI" "$RI.antes"
[ -f "$RI" ] || printf '[General]\n' > "$RI"
grep -q '^\[General\]' "$RI" || sed -i '1i [General]' "$RI"
def() { if grep -q "^$1=" "$RI"; then sed -i "s|^$1=.*|$1=$2|" "$RI"; else sed -i "/^\[General\]/a $1=$2" "$RI"; fi; }
def colorScheme Caveira; def fontFamily "Fira Code"; def fontSize 11; def TerminalTransparency 0
chown -R 0:0 "$M/root/.config"
echo "root terminal: $(grep -E '^(colorScheme|fontFamily)=' "$RI" | tr '\n' ' ')"

# papel de parede estilo Anonymous
install -d -m 0755 -o 0 -g 0 "$M/usr/share/backgrounds/caveira"
install -m 0644 -o 0 -g 0 "$PAY/kali-anonymous.png" "$M/usr/share/backgrounds/caveira/kali-anonymous.png"
XD="$M$CASA/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
if [ -f "$XD" ]; then
  sed -i -E '/name="last-image"/ s#value="[^"]*"#value="/usr/share/backgrounds/caveira/kali-anonymous.png"#' "$XD"
  chown "$KU" "$XD"
  echo "papel de parede: $(grep -c 'kali-anonymous.png' "$XD") tela(s) com o Anonymous"
fi
