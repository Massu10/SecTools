#!/usr/bin/env bash
#
# gerar-hashes.sh — cria, DENTRO do Kali, hashes de senhas que VOCÊ escolhe,
# para treinar John e Hashcat.
#
# As senhas estão todas na wordlist-lab.txt e no gabarito.md: você JÁ SABE as
# respostas. O objetivo é aprender a ferramenta e o método (formatos, modos de
# ataque, regras, máscaras) num material que é só seu — não "descobrir" segredo.
#
# Uso:    bash gerar-hashes.sh [pasta-de-saida]
# Padrão: ~/labs-cripto
#
set -euo pipefail

SAIDA="${1:-$HOME/labs-cripto}"
mkdir -p "$SAIDA"
cd "$SAIDA"
echo "[*] Gerando em: $SAIDA"

md5()    { printf '%s' "$1" | md5sum    | cut -d' ' -f1; }
sha1()   { printf '%s' "$1" | sha1sum   | cut -d' ' -f1; }
sha256() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

# sha512crypt ($6$...), o formato real do /etc/shadow. Usa openssl; cai no
# mkpasswd (pacote whois) se precisar.
sha512crypt() {
  openssl passwd -6 -salt "$(openssl rand -hex 4)" "$1" 2>/dev/null \
    || mkpasswd -m sha-512 "$1"
}

# -------- 1) hashes "crus" (raw): caem com ataque de wordlist (-a 0) --------
# Estas senhas estão LITERALMENTE na wordlist-lab.txt.
: > md5.txt; : > sha1.txt; : > sha256.txt
for s in 123456 password qwerty letmein iloveyou monkey dragon; do
  md5    "$s" >> md5.txt
  sha1   "$s" >> sha1.txt
  sha256 "$s" >> sha256.txt
done

# -------- 2) hashes que pedem REGRAS (mangling) --------
# A base está na wordlist, mas com maiúscula/número/símbolo. Só caem com
# --rules (John) ou -r <regra> (Hashcat).
{ md5 "Password1"; md5 "Dragon!"; md5 "monkey2024"; } > md5-regras.txt

# -------- 3) hash que pede MÁSCARA / força bruta curta --------
# PIN de 4 dígitos -> -a 3 ?d?d?d?d (Hashcat) / --mask=?d?d?d?d (John).
# Rápido mesmo na CPU (no máximo 10.000 tentativas).
md5 "4821" > md5-pin.txt

# -------- 4) sha512crypt (formato do /etc/shadow) --------
# John detecta sozinho; no Hashcat é -m 1800.
: > shadow-hashes.txt
i=0
for s in 123456 letmein dragon; do
  printf 'user%d:%s\n' "$i" "$(sha512crypt "$s")" >> shadow-hashes.txt
  i=$((i + 1))
done

# -------- 5) exercício unshadow (passwd + shadow -> John) --------
: > passwd.txt; : > shadow.txt
j=0
for s in qwerty iloveyou; do
  u="aluno${j}"
  printf '%s:x:100%d:100%d::/home/%s:/bin/bash\n' "$u" "$j" "$j" "$u" >> passwd.txt
  printf '%s:%s:19000:0:99999:7:::\n' "$u" "$(sha512crypt "$s")" >> shadow.txt
  j=$((j + 1))
done
if command -v unshadow >/dev/null; then
  unshadow passwd.txt shadow.txt > linux.hash
fi

# -------- 6) ZIP protegido (zip2john) --------
echo "parabens, voce abriu o cofre do lab" > segredo.txt
if command -v zip >/dev/null; then
  rm -f cofre.zip
  zip -q -P football cofre.zip segredo.txt
  if command -v zip2john >/dev/null; then
    zip2john cofre.zip > cofre.hash 2>/dev/null || true
  fi
fi
rm -f segredo.txt

# -------- 7) NTLM (bônus: formato de senha do Windows) --------
# John: --format=nt   | Hashcat: -m 1000
: > ntlm.txt
for s in 123456 password letmein; do
  python3 - "$s" >> ntlm.txt 2>/dev/null <<'PY' || true
import hashlib, sys
print(hashlib.new('md4', sys.argv[1].encode('utf-16le')).hexdigest())
PY
done
if [ ! -s ntlm.txt ]; then
  echo "(NTLM pulado: md4 indisponível neste OpenSSL — tudo bem, é bônus)"
fi

echo
echo "[ok] Arquivos criados em $SAIDA:"
ls -1
echo
echo "Respostas no gabarito.md (só olhe se travar)."
