#!/bin/bash
# Roda no Linux do WSL (root) com o disco do Kali conectado (pelo Windows: kali-acesso\aplicar-no-kali.ps1
# -Script ..\kali-visual\aplicar-autologin.sh): login automático do usuário na janela do Hyper-V (sessão aprimorada
# / xrdp), SÓ se o xrdp do Kali não escutar na rede.          Outro usuário: USUARIO_KALI=nome bash aplicar-autologin.sh
set -u
U=${USUARIO_KALI:-kali}
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
INI="$M/etc/xrdp/xrdp.ini"
PAM="$M/etc/pam.d/xrdp-sesman"
[ -f "$INI" ] && [ -f "$PAM" ] || { echo "ERRO: xrdp não encontrado no Kali"; exit 4; }
cp --update=none "$INI" "$INI.antes"; cp --update=none "$PAM" "$PAM.antes"

echo "=== antes ==="
grep -nE '^\s*(port|autorun|use_vsock)\s*=' "$INI"
awk '/^\[Xorg\]/{f=1} /^\[/{if($0!="[Xorg]")f=0} f&&/^(username|password)=/' "$INI"
head -n 5 "$PAM"

# 1. garantir que o xrdp só escuta pelo Hyper-V (vsock), nunca pela rede
PORTA=$(grep -E '^\s*port\s*=' "$INI" | head -n1 | sed 's/.*=\s*//')
if [ "$PORTA" != "vsock://-1:3389" ]; then
  sed -i -E '0,/^\s*port\s*=.*/s##port=vsock://-1:3389#' "$INI"
  echo "porta do xrdp era '$PORTA'; agora só vsock (Hyper-V)"
fi

# 2. sessão Xorg com o usuário já preenchido (a janela do Hyper-V não manda usuário e senha, então o xrdp ainda mostra
#    a tela com OK; o kali-acesso\abrir-kali.ps1 aperta o Enter sozinho)
if grep -qE '^\s*autorun\s*=' "$INI"; then sed -i -E 's#^\s*autorun\s*=.*#autorun=Xorg#' "$INI"
else sed -i '/^\[Globals\]/a autorun=Xorg' "$INI"; fi
awk -v u="$U" 'BEGIN{x=0} /^\[Xorg\]/{x=1; print; next} /^\[/{x=0} { if(x && $0 ~ /^username=/){print "username=" u; next} if(x && $0 ~ /^password=/){print "password=automatico"; next} print }' "$INI" > "$INI.novo" && cat "$INI.novo" > "$INI" && rm -f "$INI.novo"

awk '/^\[Xorg\]/{f=1;next} /^\[/{f=0} f' "$INI" | grep -q '^username=' || sed -i "/^\[Xorg\]/a username=$U" "$INI"
awk '/^\[Xorg\]/{f=1;next} /^\[/{f=0} f' "$INI" | grep -q '^password=' || sed -i '/^\[Xorg\]/a password=automatico' "$INI"

# 3. PAM do xrdp: o usuário entra sem senha SÓ por esta sessão; os outros (inclusive root) continuam com senha
if ! grep -q "pam_succeed_if.so user = $U quiet" "$PAM"; then
  sed -i "1i auth sufficient pam_succeed_if.so user = $U quiet" "$PAM"
fi

# 4. desempenho: sem efeitos de composição (transparência) no XFCE e no terminal
H="$M$CASA"
XW="$H/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
mkdir -p "$(dirname "$XW")"
[ -f "$XW" ] && cp --update=none "$XW" "$XW.antes"
python3 - "$XW" <<'PY'
import sys, os, xml.etree.ElementTree as ET
arq = sys.argv[1]
if os.path.exists(arq):
    tree = ET.parse(arq); root = tree.getroot()
else:
    root = ET.Element("channel", name="xfwm4", version="1.0"); tree = ET.ElementTree(root)
geral = next((p for p in root.findall("property") if p.get("name") == "general"), None)
if geral is None: geral = ET.SubElement(root, "property", name="general", type="empty")
p = next((q for q in geral.findall("property") if q.get("name") == "use_compositing"), None)
if p is None: p = ET.SubElement(geral, "property", name="use_compositing", type="bool")
p.set("type", "bool"); p.set("value", "false")
ET.indent(tree); tree.write(arq, encoding="UTF-8", xml_declaration=True)
print("efeitos de composição: desligados")
PY
QI="$H/.config/qterminal.org/qterminal.ini"
[ -f "$QI" ] && sed -i 's/^TerminalTransparency=.*/TerminalTransparency=0/' "$QI"
chown -R "$KU" "$H/.config/xfce4"
[ -d "$H/.config/qterminal.org" ] && chown -R "$KU" "$H/.config/qterminal.org"

echo "=== depois ==="
grep -nE '^\s*(port|autorun|use_vsock)\s*=' "$INI"
awk '/^\[Xorg\]/{f=1} /^\[/{if($0!="[Xorg]")f=0} f&&/^(username|password)=/' "$INI"
head -n 5 "$PAM"
