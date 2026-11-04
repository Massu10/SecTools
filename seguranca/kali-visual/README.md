# Tema "Máscara verde" para o Kali

Terminal verde com a máscara do V desenhada ao abrir, painel do sistema, **chuva de código nos resultados dos
comandos** e um comando para voltar tudo às cores originais do Kali. Feito para o QTerminal + zsh + XFCE do Kali.

## Instalar (pelo Windows, com o Kali no Hyper-V)

```powershell
.\instalar-tema.ps1                     # máquina "Kali", usuário "kali"; outros: -Maquina "Nome" -Usuario nome
```

Monta a pasta de arquivos em `%LOCALAPPDATA%\Blindagem\kali-mascara` (as artes do terminal pelo Python, se houver; os
papéis de parede pelo Edge ou Chrome sem janela) e chama o [../kali-acesso/aplicar-no-kali.ps1](../kali-acesso/), que
pede administrador, desliga o Kali (pergunta antes) e aplica com o disco montado no WSL. Reaplicar volta tudo ao verde.
`-SemPapel` deixa o papel de parede como está; `-Simular` só mostra o que faria.

Num Linux com o disco do Kali conectado, direto: `sudo USUARIO_KALI=kali bash aplicar-mascara.sh <pasta com os arquivos>`.

## Comandos no terminal do Kali

| Comando | O que faz |
|---|---|
| `chuva` | liga e desliga a chuva de código nos resultados (ligada por padrão; a escolha fica salva) |
| **Alt+Enter** | roda a linha digitada ao contrário: sem a chuva quando ela está ligada, com a chuva quando está desligada |
| `chuva <comando>` | só este comando com a chuva |
| `cores original` | tudo nas cores originais do Kali: terminal, prompt, digitação, `man`, papel de parede (o mesmo desenho nas cores do Kali), a chuva em azul e a máscara com as cores de verdade |
| `cores verde` | volta ao tema |
| `matrix` | descanso de tela com a chuva (q sai; + e - mudam a velocidade) |
| `mascara` / `mascara desligar` / `mascara ligar` | mostra o desenho / não mostrar ao abrir o terminal / mostrar de novo |

### Como a chuva funciona

Antes de cada comando, o zsh liga a saída dele a um terminal falso (pty) criado pelo `matrix --capturar`: o comando
continua vendo um terminal, então o `ls` mantém colunas e cores. Enquanto ele roda, uma linha de espera mostra quantas
linhas chegaram e a última (perguntas como "[s/n]" aparecem ali). Quando acaba, o resultado cai na chuva e cada letra para
no lugar certo; a tela final é igual à do comando sem a chuva. Quanto maior o resultado, mais rápida a chuva (cerca de
1 s numa linha e 2,4 s numa tela cheia; `MATRIX_TEMPO=2` deixa 2x mais lenta). Qualquer tecla pula.

Rodam sem a chuva: programas de tela cheia e interativos (vim, less, man, top, ssh, nc, msfconsole, git, apt...),
shells, comandos do próprio shell (cd, exit...), `tail -f` e linhas com `&`. Ctrl+C e Ctrl+Z funcionam; o que um
programa escrever depois de terminar o comando aparece direto. A lista fica em `_CHUVA_FORA` no
[mascara.zsh](mascara.zsh).

`comando | matrix` também faz a chuva com qualquer saída.

### Cores originais na hora

O QTerminal 2.4 não troca as cores de uma aba aberta. O `cores` troca o esquema no `qterminal.ini`, abre uma aba nova na
mesma pasta pelo D-Bus do QTerminal (`gdbus`) e fecha a atual (só se nada estiver rodando nela). As outras abas abertas
mudam quando forem reabertas.

## Arquivos

| Arquivo | O que é |
|---|---|
| [instalar-tema.ps1](instalar-tema.ps1) | instalador pelo Windows |
| [aplicar-mascara.sh](aplicar-mascara.sh) | instala no disco do Kali (o instalador chama) |
| [mascara.zsh](mascara.zsh) | prompt, desenho, chuva, `cores` (vai para `/usr/local/share/mascara`; os `.zshrc` só têm uma linha que lê este arquivo) |
| [matrix](matrix) | a chuva (Python, sem bibliotecas; vai para `/usr/local/bin`) |
| [Mascara.colorscheme](Mascara.colorscheme), [MascaraRoot.colorscheme](MascaraRoot.colorscheme) | esquemas do QTerminal (usuário e root) |
| [mascara-mapa.txt](mascara-mapa.txt), [gerar-arte-terminal.py](gerar-arte-terminal.py), `mascara-*.ans` | o desenho da máscara (mapa de pixels) e as artes do terminal geradas dele |
| [papel-mascara.html](papel-mascara.html) | os papéis de parede (1920x1080; o das cores originais com `#original` no fim do endereço) |
| [gerar-icone.py](gerar-icone.py), [kali-mascara.ico](kali-mascara.ico) | o ícone do atalho "Kali Linux" |
| [aplicar-autologin.sh](aplicar-autologin.sh) | login do xrdp já preenchido (veja [../kali-acesso/](../kali-acesso/)) |
| [aplicar-sombrio.sh](aplicar-sombrio.sh), `bloco-*.zsh`, [Caveira.colorscheme](Caveira.colorscheme), `kali-anonymous.*`, `kali-caveira*` | o tema anterior, "Anonymous sombrio" |
| [powershell-moderno.ico](powershell-moderno.ico), [cmd-moderno.ico](cmd-moderno.ico) | ícones para atalhos do PowerShell e do Prompt de Comando no Windows |

Desfazer: os arquivos alterados têm uma cópia `.antes-verde`; apagar a linha `mascara verde` dos `.zshrc` desliga tudo.
