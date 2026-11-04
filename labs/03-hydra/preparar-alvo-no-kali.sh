#!/usr/bin/env bash
#
# preparar-alvo-no-kali.sh — monta um ALVO DE TREINO no PRÓPRIO Kali, para o Hydra.
#
# Cria um usuário descartável com senha fraca e liga o SSH. Você vai mirar o Hydra em
# 127.0.0.1 (a própria máquina): nada sai para a rede, nada de terceiros é tocado.
# A senha do usuário "treino" está na senhas.txt — o exercício é o Hydra "achá-la".
#
# Montar:   sudo bash preparar-alvo-no-kali.sh
# Desfazer: sudo bash preparar-alvo-no-kali.sh --remover
#
set -euo pipefail

USUARIO="treino"
SENHA="dragon"     # está na senhas.txt e na ../comum/wordlist-lab.txt

if [ "$(id -u)" -ne 0 ]; then
  echo "Rode com sudo:  sudo bash preparar-alvo-no-kali.sh [--remover]"
  exit 1
fi

if [ "${1:-}" = "--remover" ]; then
  deluser --remove-home "$USUARIO" 2>/dev/null || true
  echo "[ok] Usuário '$USUARIO' removido."
  echo "    O SSH continua como estava. Para desligá-lo: sudo systemctl disable --now ssh"
  exit 0
fi

# usuário de treino (idempotente)
id "$USUARIO" >/dev/null 2>&1 || useradd -m -s /bin/bash "$USUARIO"
echo "${USUARIO}:${SENHA}" | chpasswd

# liga o SSH (no Kali o serviço chama 'ssh')
systemctl enable --now ssh

echo
echo "[ok] Alvo de treino pronto."
echo "    Serviço : SSH em 127.0.0.1:22"
echo "    Usuário : $USUARIO   (senha fraca, presente na senhas.txt)"
echo
echo "    Treine:   hydra -l $USUARIO -P senhas.txt ssh://127.0.0.1"
echo "    Desfaça:  sudo bash preparar-alvo-no-kali.sh --remover"
echo
echo "    Dica de isolamento: se quiser que o SSH nem apareça na rede Lab, edite"
echo "    /etc/ssh/sshd_config e ponha 'ListenAddress 127.0.0.1', depois:"
echo "    sudo systemctl restart ssh"
