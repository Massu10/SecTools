# Lab 1 — John the Ripper

Quebrar hashes de senha que **você mesmo gerou** (ver [regra de ouro](../README.md)).
John detecta o formato sozinho na maioria dos casos e é ótimo para começar.

**Prepare uma vez:**
```bash
bash ../comum/gerar-hashes.sh     # cria ~/labs-cripto
cd ~/labs-cripto
WL=~/Documents/.../labs/comum/wordlist-lab.txt   # ajuste o caminho da wordlist do lab
ROCK=/usr/share/wordlists/rockyou.txt
```
(Dica: copie a `wordlist-lab.txt` para dentro do Kali, ex. `~/labs-cripto/wordlist-lab.txt`,
e use `WL=~/labs-cripto/wordlist-lab.txt`.)

Como John guarda o que já quebrou no `~/.john/john.pot`, para **refazer** um exercício
do zero use `--pot=/tmp/lab.pot` ou apague a linha correspondente do pot.

---

## Conceitos que este lab fixa

- **Formato do hash** (`--format=`): MD5 cru é `Raw-MD5`, SHA1 é `Raw-SHA1`, o `$6$` do
  shadow é `sha512crypt`. John adivinha, mas em hash cru às vezes erra — aí você diz.
- **Modos de ataque**: wordlist (`--wordlist`), wordlist + regras (`--rules`),
  máscara (`--mask`), incremental/força bruta (`--incremental`).
- **Ver o resultado**: `--show` relê o `.pot` e mostra senha ao lado do hash.

---

## Exercício 1.1 — wordlist em hash cru (MD5, SHA1, SHA256)

```bash
john --format=Raw-MD5    --wordlist=$WL md5.txt
john --format=Raw-SHA1   --wordlist=$WL sha1.txt
john --format=Raw-SHA256 --wordlist=$WL sha256.txt

john --show --format=Raw-MD5 md5.txt      # ver as senhas achadas
```
Esperado: as 7 senhas caem na hora. **Observe**: o mesmo ataque, mudando só o
`--format`, serve para qualquer um dos três. O custo de testar muda pouco — hash cru
é rápido demais, por isso é ruim para guardar senha.

## Exercício 1.2 — regras (mangling)

A wordlist tem `password`, `dragon`, `monkey`, mas os hashes são de `Password1`,
`Dragon!`, `monkey2024`. Sem regra, não cai:
```bash
john --format=Raw-MD5 --wordlist=$WL md5-regras.txt          # provavelmente 0
john --format=Raw-MD5 --wordlist=$WL --rules md5-regras.txt  # agora sim
```
`--rules` aplica transformações (primeira maiúscula, anexar dígitos/símbolos, trocar
`a`->`@`...). É o pulo do gato: uma wordlist pequena cobre as variações que as pessoas
realmente usam. Veja/edite as regras em `/etc/john/john.conf` (seção `[List.Rules]`).

## Exercício 1.3 — máscara / força bruta curta (PIN)

`4821` não está em dicionário nenhum. Trate como 4 dígitos:
```bash
john --format=Raw-MD5 --mask='?d?d?d?d' md5-pin.txt
```
`?d` = um dígito. São 10.000 combinações — termina num piscar. **Lição**: força bruta
só é viável quando o espaço é pequeno (PIN curto, charset conhecido). Aumente para
`?d?d?d?d?d?d` e sinta o espaço crescer 100x.

## Exercício 1.4 — sha512crypt (o formato do /etc/shadow)

```bash
john --wordlist=$WL shadow-hashes.txt     # John detecta sha512crypt sozinho
john --show shadow-hashes.txt
```
Repare como é **bem mais lento** que o MD5, mesmo com a mesma wordlist. É de propósito:
`$6$` roda milhares de iterações. Por isso aqui você usa wordlist dirigida, nunca força
bruta cega. Para sentir a diferença de velocidade, compare o "p/s" (tentativas por
segundo) que o John mostra com `Enter` durante a execução.

## Exercício 1.5 — unshadow (fluxo real do Linux)

No ataque real a uma máquina Linux você junta `/etc/passwd` e `/etc/shadow` (aqui são
cópias de treino que o script criou). O `gerar-hashes.sh` já rodou o `unshadow`:
```bash
cat linux.hash                 # veja o formato usuario:$6$...
john --wordlist=$WL linux.hash
john --show linux.hash
```

## Exercício 1.6 — arquivo ZIP protegido

John quebra senha de muitos formatos através dos utilitários `*2john`:
```bash
# o script já gerou cofre.hash com:  zip2john cofre.zip > cofre.hash
john --wordlist=$WL cofre.hash
john --show cofre.hash
```
Tente também `rar2john`, `ssh2john` (senha de chave privada), `office2john`. É o mesmo
padrão: extrai o hash do arquivo e entrega ao John.

## Exercício 1.7 — rockyou (wordlist de verdade)

```bash
john --format=Raw-MD5 --wordlist=$ROCK md5.txt
```
A rockyou tem ~14 milhões de senhas vazadas. Mostra por que senha comum não resiste:
ela provavelmente já está na lista.

---

## Cola de comandos

| Objetivo | Comando |
|---|---|
| Wordlist | `john --wordlist=LISTA arquivo.hash` |
| Wordlist + regras | `john --wordlist=LISTA --rules arquivo.hash` |
| Máscara | `john --mask='?l?l?l?d?d' arquivo.hash` |
| Forçar formato | `john --format=Raw-MD5 arquivo.hash` |
| Ver achados | `john --show arquivo.hash` |
| Listar formatos | `john --list=formats` |
| Pot isolado (refazer) | `john --pot=/tmp/lab.pot ...` |

Símbolos de máscara: `?l` minúscula, `?u` maiúscula, `?d` dígito, `?s` símbolo, `?a` tudo.

Próximo: [../02-hashcat](../02-hashcat/) faz os mesmos ataques com a lógica do Hashcat.
