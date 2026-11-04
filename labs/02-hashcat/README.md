# Lab 2 — Hashcat

Os mesmos hashes do [Lab 1](../01-john/) (de `~/labs-cripto`, gerados por você), agora
com a lógica do Hashcat: você escolhe **o modo do hash** (`-m`) e **o modo de ataque**
(`-a`) na mão. É mais verboso que o John, mas é o padrão quando há GPU.

**GPU x CPU (importante no seu caso):** no Kali dentro do Hyper-V normalmente **não há
GPU** disponível, então o Hashcat roda na CPU (use `--force` se ele reclamar da falta de
dispositivo). Para os exercícios aqui isso basta — os hashes são pequenos. Se um dia
quiser velocidade real, o Hashcat roda muito bem **no Windows** usando sua Radeon RX 7600
(baixe o Hashcat oficial e rode no PowerShell). O aprendizado é idêntico.

Como o Hashcat guarda o que já quebrou no `~/.local/share/hashcat/hashcat.potfile`, para
**refazer** um exercício use `--potfile-path=/tmp/lab.pot`.

```bash
cd ~/labs-cripto
WL=~/labs-cripto/wordlist-lab.txt       # copie a wordlist do lab para cá
ROCK=/usr/share/wordlists/rockyou.txt
```

---

## Modos de hash (`-m`) que aparecem aqui

| `-m` | Formato | Arquivo |
|---|---|---|
| 0 | MD5 | `md5.txt`, `md5-regras.txt`, `md5-pin.txt` |
| 100 | SHA1 | `sha1.txt` |
| 1400 | SHA256 | `sha256.txt` |
| 1800 | sha512crypt (`$6$`) | `shadow-hashes.txt` |
| 1000 | NTLM | `ntlm.txt` |

Modos de ataque (`-a`): **0** = wordlist (straight), **3** = máscara/força bruta,
**6/7** = combinador wordlist+máscara.

---

## Exercício 2.1 — wordlist (straight)

```bash
hashcat -m 0   -a 0 md5.txt    $WL
hashcat -m 100 -a 0 sha1.txt   $WL
hashcat -m 1400 -a 0 sha256.txt $WL

hashcat -m 0 --show md5.txt            # ver o que caiu
```
Se ele disser "No devices found/left", acrescente `--force` (roda na CPU).

## Exercício 2.2 — wordlist + regras

Mesma ideia do `--rules` do John, aqui com arquivos de regra prontos:
```bash
hashcat -m 0 -a 0 md5-regras.txt $WL -r /usr/share/hashcat/rules/best64.rule
hashcat -m 0 --show md5-regras.txt
```
`best64.rule` são 64 transformações muito eficazes. Veja também `rockyou-30000.rule`
(bem maior). **Lição**: `wordlist pequena × regras` cobre o jeito real de as pessoas
"temperarem" senhas.

## Exercício 2.3 — máscara (o PIN)

```bash
hashcat -m 0 -a 3 md5-pin.txt '?d?d?d?d'
```
`-a 3` é ataque de máscara. `?d?d?d?d` = 4 dígitos (10.000 tentativas). Experimente
máscaras maiores e veja o tempo estimado subir — o Hashcat mostra "Progress" e ETA.
Charsets: `?l ?u ?d ?s ?a`. Dá para definir os seus (`-1 ?l?d` cria o charset `?1`).

## Exercício 2.4 — sha512crypt (hash lento)

```bash
hashcat -m 1800 -a 0 shadow-hashes.txt $WL --username
```
`--username` faz ele ignorar o `usuario:` no começo da linha. Note a velocidade
despencar para pouquíssimas tentativas por segundo — é o KDF lento trabalhando a seu
favor (do lado da defesa). Por isso, contra `$6$`, só wordlist dirigida + regras.

## Exercício 2.5 — NTLM (senha do Windows)

```bash
hashcat -m 1000 -a 0 ntlm.txt $WL
hashcat -m 1000 --show ntlm.txt
```
NTLM é rápido e **sem sal** — por isso hash vazado de Windows cai fácil. É o mesmo
formato que o Lab 4 pode colher da memória de um alvo.

## Exercício 2.6 — rockyou de verdade

```bash
hashcat -m 0 -a 0 md5.txt $ROCK
```

---

## Cola de comandos

| Objetivo | Comando |
|---|---|
| Wordlist | `hashcat -m MODO -a 0 hashes LISTA` |
| Wordlist + regras | `hashcat -m MODO -a 0 hashes LISTA -r REGRA.rule` |
| Máscara | `hashcat -m MODO -a 3 hashes '?u?l?l?l?d?d'` |
| Ver achados | `hashcat -m MODO --show hashes` |
| Ignorar `usuario:` | acrescente `--username` |
| Rodar na CPU | acrescente `--force` |
| Procurar o modo certo | `hashcat --help | grep -i md5` |
| Refazer do zero | `--potfile-path=/tmp/lab.pot` |

Próximo: [../03-hydra](../03-hydra/) — sai da quebra de hash (offline) e vai para
força bruta de **login online**, contra um alvo que você monta.
