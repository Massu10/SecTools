# Labs de prática (cibersegurança)

Exercícios para treinar **John the Ripper**, **Hashcat**, **Hydra** e **Metasploit**
num ambiente **só seu e isolado**: o Kali no Hyper-V (como montar:
[../seguranca/kali-acesso/README.md](../seguranca/kali-acesso/README.md)).

> **Regra de ouro.** Tudo aqui acontece dentro do *seu* laboratório. Você quebra hashes
> de senhas que *você mesmo* gerou (já sabe as respostas) e ataca alvos que *você mesmo*
> montou, na rede privada **Lab** do Hyper-V — que não alcança a internet, nem o Windows,
> nem ninguém. O objetivo é **entender o ataque para saber defender**; não existe nenhum
> alvo externo nestes exercícios. Apontar essas ferramentas para sistema de terceiros sem
> autorização por escrito é crime (no Brasil, art. 154-A do Código Penal). Em curso, CTF ou
> pentest, guarde o aceite/escopo por escrito antes de qualquer teste.

## Como se encaixa no seu PC

O Kali tem duas placas de rede ([montar o Kali](../seguranca/kali-acesso/README.md)):

| Placa | Rede Hyper-V | Serve para | IP sugerido |
|---|---|---|---|
| Internet | `KaliNAT` (interna, NAT) | baixar/atualizar (`apt`) | 192.168.150.10/24 |
| Lab | `Lab` (privada, só entre VMs) | **o laboratório** | 10.10.10.10/24 |

Os labs 1 e 2 (quebra de hash) rodam **só dentro do Kali** — não precisam de rede nenhuma.
Os labs 3 e 4 usam um alvo:
- **Hydra**: um alvo de treino no *próprio Kali* (script pronto), mirando `127.0.0.1`.
- **Metasploit**: a VM **Metasploitable 2** na rede privada **Lab** (`10.10.10.20`), sem
  saída para a internet. Como montar: [04-metasploit/montar-metasploitable.md](04-metasploit/montar-metasploitable.md).

A rede `Lab` é um switch **privado** do Hyper-V: não tem DHCP e não fala com o host. Por isso
os dois lados usam **IP fixo** (Kali `10.10.10.10`, alvo `10.10.10.20`). Se o alvo não
conseguir pingar `8.8.8.8`, está certo — é o isolamento funcionando.

## Trilha

| # | Pasta | Ferramenta | O que treina | Precisa de alvo? |
|---|---|---|---|---|
| 1 | [01-john](01-john/) | John the Ripper | formatos de hash, wordlist, regras, máscara | Não |
| 2 | [02-hashcat](02-hashcat/) | Hashcat | modos de hash e de ataque, regras, máscara | Não |
| 3 | [03-hydra](03-hydra/) | Hydra | força bruta de login online (SSH/FTP/HTTP) | Sim — alvo local |
| 4 | [04-metasploit](04-metasploit/) | Metasploit | recon, exploração, pós-exploração | Sim — Metasploitable 2 |

Sugestão: faça **01 e 02 primeiro** (só precisam do Kali). Depois monte o alvo e faça 03 e 04.

## Antes de começar (uma vez, dentro do Kali)

```bash
sudo apt update
sudo apt install -y john hashcat hydra metasploit-framework zip qemu-utils
# a rockyou vem compactada no Kali:
[ -f /usr/share/wordlists/rockyou.txt ] || sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz
```

No Kali "completo" essas ferramentas já vêm instaladas; o comando acima só garante.

Depois, gere os hashes de treino (só seus, respostas conhecidas):

```bash
bash comum/gerar-hashes.sh          # cria ~/labs-cripto com todos os arquivos
```

As respostas ficam em [comum/gabarito.md](comum/gabarito.md) — só olhe se travar.

## Pastas

```
labs/
  comum/            scripts e wordlist compartilhados pelos labs 1 e 2
  01-john/          John the Ripper
  02-hashcat/       Hashcat
  03-hydra/         Hydra (+ script que monta o alvo de treino no Kali)
  04-metasploit/    Metasploit (+ guia para montar a Metasploitable 2)
```
