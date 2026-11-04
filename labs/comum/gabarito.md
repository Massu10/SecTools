# Gabarito (só olhe se travar)

Todas as senhas abaixo foram **escolhidas por você** e geradas pelo
[gerar-hashes.sh](gerar-hashes.sh). O valor do exercício é chegar nelas com a
ferramenta — ver a resposta aqui não ensina nada. Use só para conferir ou destravar.

## Arquivos em `~/labs-cripto`

| Arquivo | Formato | Senhas (em ordem) | Como cai |
|---|---|---|---|
| `md5.txt` | MD5 cru | 123456, password, qwerty, letmein, iloveyou, monkey, dragon | wordlist (`-a 0`) |
| `sha1.txt` | SHA1 cru | (as mesmas 7) | wordlist |
| `sha256.txt` | SHA256 cru | (as mesmas 7) | wordlist |
| `md5-regras.txt` | MD5 cru | Password1, Dragon!, monkey2024 | wordlist **+ regras** |
| `md5-pin.txt` | MD5 cru | 4821 | **máscara** `?d?d?d?d` |
| `shadow-hashes.txt` | sha512crypt (`$6$`) | 123456, letmein, dragon | wordlist (lento de propósito) |
| `linux.hash` | unshadow (sha512crypt) | qwerty, iloveyou | wordlist |
| `cofre.hash` | ZIP (PKZIP) | football | wordlist |
| `ntlm.txt` | NTLM | 123456, password, letmein | wordlist (`-m 1000` / `--format=nt`) |

## Por que estas senhas

- **Diretas na wordlist** (123456, password, qwerty...): mostram o caso mais comum —
  senha fraca que está num dicionário. Caem em segundos.
- **Com regras** (Password1, Dragon!, monkey2024): a base (`password`, `dragon`,
  `monkey`) está na wordlist, mas o humano "temperou" com maiúscula/número/símbolo.
  Ensina **mangling** (`--rules` no John, `-r best64.rule` no Hashcat) — como uma
  wordlist pequena vira milhões de variações.
- **PIN 4821**: não está em dicionário nenhum. Ensina **máscara/força bruta** num
  espaço pequeno (10.000 combinações) que termina rápido até sem GPU.
- **sha512crypt** (`$6$`): o formato real do `/etc/shadow`. É **lento de propósito**
  (KDF com milhares de rodadas) — mostra na prática por que hash de senha bom é lento,
  e por que você só tenta poucas candidatas boas, não força bruta cega.
