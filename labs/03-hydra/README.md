# Lab 3 — Hydra

Até aqui a quebra era **offline** (você tinha o hash). Hydra é diferente: testa
usuário/senha **online**, falando com um serviço de login de verdade (SSH, FTP,
HTTP...). Por isso precisa de um **alvo** — e o alvo é seu.

> **Escopo.** Só o alvo que você montou. Nos exercícios abaixo o alvo é `127.0.0.1`
> (o próprio Kali) ou a VM Metasploitable em `10.10.10.20` na rede privada **Lab**.
> Nunca um endereço que não seja do seu laboratório. (ver [regra de ouro](../README.md))

## Monte o alvo de treino (no próprio Kali)

```bash
sudo bash preparar-alvo-no-kali.sh      # cria o usuário 'treino' e liga o SSH
```
Isso sobe um SSH em `127.0.0.1:22` com o usuário `treino`, cuja senha fraca está na
[senhas.txt](senhas.txt). Ao terminar:
```bash
sudo bash preparar-alvo-no-kali.sh --remover
```

---

## Conceitos que este lab fixa

- **Login online x hash offline**: aqui cada tentativa é uma conexão de rede, então é
  **lento** e **barulhento** (aparece em log, pode travar a conta). Nada de milhões de
  tentativas — use listas curtas e dirigidas.
- **Anatomia do comando**: `hydra [-l user | -L lista] [-p senha | -P lista] <serviço>://<alvo>`.
- **Controles**: `-t` tarefas em paralelo, `-f` para no primeiro acerto, `-V` mostra
  cada tentativa, `-s` porta diferente.

---

## Exercício 3.1 — SSH, senha conhecida o usuário

```bash
hydra -l treino -P senhas.txt ssh://127.0.0.1 -t 4 -f -V
```
`-l treino` fixa o usuário; `-P senhas.txt` varre as senhas; `-f` para ao achar. Observe
no `-V` cada par testado. Deve achar `dragon`.

## Exercício 3.2 — usuário também desconhecido

```bash
hydra -L usuarios.txt -P senhas.txt ssh://127.0.0.1 -t 4
```
Agora ele cruza [usuarios.txt](usuarios.txt) × [senhas.txt](senhas.txt). **Lição**: o
espaço de busca é usuários × senhas — cresce rápido. Por isso, no mundo real, listas
curtas e inteligência prévia (nomes certos) valem mais que força bruta.

## Exercício 3.3 — contra a Metasploitable (se você montou o Lab 4)

A Metasploitable 2 tem contas fracas de propósito. Pela rede **Lab**:
```bash
hydra -l msfadmin -P senhas.txt ssh://10.10.10.20
hydra -l user     -P senhas.txt ftp://10.10.10.20
```
(credencial clássica dela: `msfadmin`/`msfadmin` — acrescente na senhas.txt para ver cair.)

## Exercício 3.4 — formulário HTTP (DVWA)

Login web é `http-post-form`. O formato é
`"<caminho>:<corpo do POST com ^USER^ e ^PASS^>:<texto que indica FALHA>"`. Exemplo
contra a DVWA (que você suba localmente ou na Metasploitable):
```bash
hydra -l admin -P senhas.txt 10.10.10.20 http-post-form \
  "/dvwa/login.php:username=^USER^&password=^PASS^&Login=Login:Login failed"
```
**Lição**: o terceiro campo é como o Hydra sabe que errou — ajuste-o ao texto/retorno
real da página (veja o POST no DevTools do navegador, aba Rede).

---

## Cola de comandos

| Objetivo | Comando |
|---|---|
| Usuário fixo, varrer senhas | `hydra -l USER -P senhas.txt ssh://ALVO` |
| Varrer os dois | `hydra -L usuarios.txt -P senhas.txt ssh://ALVO` |
| Parar no 1º acerto | acrescente `-f` |
| Ver cada tentativa | acrescente `-V` |
| Menos agressivo | `-t 4` (ou menos) |
| Outra porta | `-s 2222` |
| Serviços suportados | `hydra` (sem argumentos) lista todos |

Serviços comuns: `ssh`, `ftp`, `telnet`, `smb`, `mysql`, `postgres`, `rdp`,
`http-get`, `http-post-form`.

> Cuidado real: `-t` alto e muitas senhas podem **travar contas** e derrubar o serviço.
> Mesmo no seu lab, pegue o costume de ir devagar — é o que se exige num teste autorizado.

Próximo: [../04-metasploit](../04-metasploit/).
