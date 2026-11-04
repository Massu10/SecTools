#!/bin/bash
# Roda no Linux do WSL (root) com o disco do Kali conectado (wsl --mount --vhd <disco> --bare); o jeito fácil é pelo
# Windows: kali-visual\instalar-tema.ps1 (monta a pasta de arquivos e chama o kali-acesso\aplicar-no-kali.ps1).
# Tema "Máscara verde": terminal verde do usuário e do root, desenho da máscara, papel de parede e os comandos
# matrix, chuva e cores (chuva de código em todo resultado, ligada por padrão, e "cores original", que põe tudo nas
# cores do Kali na hora: terminal, prompt, papel de parede e a máscara colorida de verdade).
# Uso: bash aplicar-mascara.sh <pasta com os arquivos>        Outro usuário: USUARIO_KALI=nome bash aplicar-mascara.sh ...
# A pasta precisa ter também os .ans (gerar-arte-terminal.py). Os papéis de parede são opcionais (sem eles, ficam como
# estão): kali-mascara-verde.png e kali-mascara-original.png (o mesmo desenho nas cores do Kali, para o "cores
# original"), gerados do papel-mascara.html (o original com #original no fim do endereço).
set -u
PAY=${1:?informe a pasta com os arquivos}
U=${USUARIO_KALI:-kali}
PAPEL=/usr/share/backgrounds/mascara/kali-mascara-verde.png
PAPEL_ORIGINAL=/usr/share/backgrounds/mascara/kali-mascara-original.png
M=/mnt/kali-disco
for f in Mascara.colorscheme MascaraRoot.colorscheme mascara.zsh mascara-kali.ans mascara-root.ans \
         mascara-real.ans mascara-real-root.ans matrix; do
  [ -f "$PAY/$f" ] || { echo "ERRO: falta $PAY/$f"; exit 1; }
done

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
echo "Kali em $ACHOU: $(grep '^PRETTY_NAME=' "$M/etc/os-release" | cut -d= -f2)"

KU=$(awk -F: -v u="$U" '$1==u{print $3":"$4}' "$M/etc/passwd")
CASA=$(awk -F: -v u="$U" '$1==u{print $6}' "$M/etc/passwd")
[ -n "$KU" ] && [ -n "$CASA" ] || { echo "ERRO: o usuário '$U' não existe no Kali (use USUARIO_KALI=nome)"; exit 4; }
echo "usuário: $U ($CASA)"
guarda() { [ -f "$1" ] && cp --update=none -p "$1" "$1.antes-verde"; }

# 1. cores do terminal
for d in qtermwidget5 qtermwidget6; do
  [ -d "$M/usr/share/$d/color-schemes" ] || continue
  install -m 0644 -o 0 -g 0 "$PAY/Mascara.colorscheme" "$PAY/MascaraRoot.colorscheme" "$M/usr/share/$d/color-schemes/"
  echo "esquemas Mascara e MascaraRoot em $d"
done

# 2. desenho, prompt e comandos (arquivos do sistema: só o root altera)
install -d -m 0755 -o 0 -g 0 "$M/usr/local/share/mascara"
install -m 0644 -o 0 -g 0 "$PAY/mascara.zsh" "$PAY/mascara-kali.ans" "$PAY/mascara-root.ans" \
  "$PAY/mascara-real.ans" "$PAY/mascara-real-root.ans" "$M/usr/local/share/mascara/"
install -m 0755 -o 0 -g 0 "$PAY/matrix" "$M/usr/local/bin/matrix"
echo "instalados: /usr/local/share/mascara/ e /usr/local/bin/matrix"

# 3. .zshrc do usuário e do root: sai o bloco antigo (caveira), entra uma linha que lê o mascara.zsh
for Z in "$M$CASA/.zshrc" "$M/root/.zshrc"; do
  [ -f "$Z" ] || { echo "AVISO: $Z não existe"; continue; }
  ini=$(grep -c '^# >>> caveira' "$Z"); fim=$(grep -c '^# <<< caveira' "$Z")
  if [ "$ini" != "$fim" ]; then echo "AVISO: blocos caveira incompletos em $Z; não mexi nele"; continue; fi
  guarda "$Z"
  dono=$(stat -c '%u:%g' "$Z"); modo=$(stat -c '%a' "$Z")
  sed -i '/^# >>> caveira/,/^# <<< caveira/d; /^# >>> mascara verde/,/^# <<< mascara verde/d' "$Z"
  printf '%s\n' '# >>> mascara verde >>>' \
    '[[ -r /usr/local/share/mascara/mascara.zsh ]] && source /usr/local/share/mascara/mascara.zsh' \
    '# <<< mascara verde <<<' >> "$Z"
  chown "$dono" "$Z"; chmod "$modo" "$Z"
  echo "${Z#$M}: caveira=$(grep -c caveira "$Z") mascara=$(grep -c 'mascara verde' "$Z")"
done

# 4. QTerminal: esquema de cores (usuário = Mascara, root = MascaraRoot), sem transparência
ajusta_ini() {
  local I=$1 esquema=$2 dono=$3
  mkdir -p "$(dirname "$I")"
  guarda "$I"
  [ -f "$I" ] || printf '[General]\n' > "$I"
  grep -q '^\[General\]' "$I" || sed -i '1i [General]' "$I"
  local k v
  for kv in "colorScheme=$esquema" "TerminalTransparency=0"; do
    k=${kv%%=*}; v=${kv#*=}
    if grep -q "^$k=" "$I"; then sed -i "s|^$k=.*|$k=$v|" "$I"; else sed -i "/^\[General\]/a $k=$v" "$I"; fi
  done
  chown -R "$dono" "$(dirname "$I")"
  echo "${I#$M}: $(grep -E '^(colorScheme|fontFamily|fontSize)=' "$I" | tr '\n' ' ')"
}
ajusta_ini "$M$CASA/.config/qterminal.org/qterminal.ini" Mascara "$KU"
ajusta_ini "$M/root/.config/qterminal.org/qterminal.ini" MascaraRoot 0:0
# tema verde de novo também no prompt: apaga a escolha do "cores original", se houver
for f in "$M$CASA/.mascara-cores-originais" "$M/root/.mascara-cores-originais"; do
  [ -e "$f" ] && rm -f "$f" && echo "${f#$M}: apagado (volta ao verde)"
done

# 5. papel de parede (só se o PNG veio na pasta)
XD="$M$CASA/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
if [ ! -f "$PAY/kali-mascara-verde.png" ]; then
  echo "papel de parede: sem kali-mascara-verde.png na pasta, fica como está"
elif [ -f "$XD" ]; then
  install -d -m 0755 -o 0 -g 0 "$M$(dirname "$PAPEL")"
  install -m 0644 -o 0 -g 0 "$PAY/kali-mascara-verde.png" "$M$PAPEL"
  guarda "$XD"
  echo "papel antes: $(grep -o 'name="last-image"[^>]*' "$XD" | sed 's/.*value="//; s/"$//' | sort -u | tr '\n' ' ')"
  sed -i -E "/name=\"last-image\"/ s#value=\"[^\"]*\"#value=\"$PAPEL\"#" "$XD"
  chown "$KU" "$XD"
  echo "papel agora em $(grep -c "value=\"$PAPEL\"" "$XD") tela(s)"
else
  install -d -m 0755 -o 0 -g 0 "$M$(dirname "$PAPEL")"
  install -m 0644 -o 0 -g 0 "$PAY/kali-mascara-verde.png" "$M$PAPEL"
  echo "AVISO: $XD não existe (escolher o papel pelo Kali: botão direito na área de trabalho)"
fi

if [ -f "$PAY/kali-mascara-original.png" ]; then
  install -d -m 0755 -o 0 -g 0 "$M$(dirname "$PAPEL_ORIGINAL")"
  install -m 0644 -o 0 -g 0 "$PAY/kali-mascara-original.png" "$M$PAPEL_ORIGINAL"
  echo "papel do cores original: $PAPEL_ORIGINAL"
fi

# 5b. o "cores original" usa: o esquema padrão do QTerminal do Kali (/etc/xdg), o gdbus (abre a aba nova já com as
#     cores, porque o QTerminal 2.4 não troca as de uma aba aberta), o xfconf-query e o papel de parede padrão do Kali
echo "esquema original do QTerminal: $(sed -n 's/^colorScheme=//p' "$M/etc/xdg/qterminal.org/qterminal.ini" 2>/dev/null | head -n 1)" \
  "| Kali-Dark: $(ls "$M"/usr/share/qtermwidget*/color-schemes/Kali-Dark.colorscheme 2>/dev/null | wc -l) arquivo(s)" \
  "| qterminal $(chroot "$M" dpkg-query -W -f '${Version}' qterminal 2>/dev/null)"
for p in usr/bin/gdbus usr/bin/xfconf-query usr/share/backgrounds/kali-16x9/default; do
  if [ -e "$M/$p" ]; then echo "tem /$p"; else echo "AVISO: falta /$p (o cores original faz menos sem ele)"; fi
done

# 6. teste: o zsh do próprio Kali lê o arquivo sem erro e o desenho sai
mount -t proc proc "$M/proc"
chroot "$M" /usr/bin/zsh -n /usr/local/share/mascara/mascara.zsh && echo "sintaxe do mascara.zsh: ok"
chroot "$M" /usr/bin/python3 -c "import ast,sys; ast.parse(open('/usr/local/bin/matrix').read())" && echo "sintaxe do matrix: ok"
chroot --userspec="$KU" "$M" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$CASA" USER="$U" TERM=xterm-256color COLUMNS=110 LANG=C.UTF-8 \
  /usr/bin/zsh -i -c 'print -r -- "PROMPT=$PROMPT"' > "$PAY/prova-usuario.txt" 2>&1
chroot "$M" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root USER=root TERM=xterm-256color COLUMNS=110 LANG=C.UTF-8 \
  /usr/bin/zsh -i -c 'print -r -- "PROMPT=$PROMPT"' > "$PAY/prova-root.txt" 2>&1
echo "teste gravado em prova-usuario.txt e prova-root.txt"
