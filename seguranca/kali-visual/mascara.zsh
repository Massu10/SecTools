# Máscara verde: tema do terminal do kali e do root (instalado por aplicar-mascara.sh, 01/11/2026; chuva e cores em 04/11/2026).
# Comandos: mascara (mostra o desenho) | mascara desligar | mascara ligar | matrix (descanso de tela)
#           chuva            liga/desliga a chuva de código nos resultados (ligada: todo comando; a escolha fica salva)
#           chuva <comando>  só este comando com a chuva    Alt+Enter: esta linha ao contrário (com ou sem a chuva)
#           cores original   tudo nas cores originais do Kali (terminal, prompt, digitação, man, papel de parede) e a
#                            máscara com as cores de verdade | cores verde  volta ao tema
# Arquivo do sistema (dono root, 0644): o .zshrc do root também lê este arquivo, então só o root pode alterá-lo.
[[ -o interactive ]] || return 0

typeset -g _MASCARA_DIR=/usr/local/share/mascara
typeset -g _MASCARA_PAPEL_VERDE=/usr/share/backgrounds/mascara/kali-mascara-verde.png
typeset -g _MASCARA_PAPEL_ORIGINAL=/usr/share/backgrounds/mascara/kali-mascara-original.png   # o mesmo, nas cores do Kali
zmodload zsh/zselect 2>/dev/null                    # pausas de centésimos de segundo sem chamar o sleep

# cores originais do Kali (o .zshrc as definiu antes desta linha), guardadas uma vez para o "cores original"
if (( ! ${+_MASCARA_ORIGINAL} )); then
  typeset -gA _MASCARA_ORIGINAL _MASCARA_ORIGINAL_HL
  _MASCARA_ORIGINAL=(PROMPT "$PROMPT" RPROMPT "$RPROMPT")
  (( ${+ZSH_HIGHLIGHT_STYLES} )) && _MASCARA_ORIGINAL_HL=("${(@kv)ZSH_HIGHLIGHT_STYLES}")
  () {
    local v
    for v in ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE GROFF_NO_SGR LESS_TERMCAP_{mb,md,me,so,se,us,ue}; do
      [[ -v $v ]] && _MASCARA_ORIGINAL[$v]=${(P)v}
    done
  }
fi
# o prompt e o precmd do Kali ganham outro nome (functions -c copia sem estragar os ┌──; functions[x]=... estraga)
if (( ${+functions[configure_prompt]} && ! ${+functions[_mascara_prompt_kali]} )) &&
   [[ ${functions[configure_prompt]} != *_mascara_prompt_verde* ]]; then
  functions -c configure_prompt _mascara_prompt_kali 2>/dev/null ||
    eval "_mascara_prompt_kali() { ${functions[configure_prompt]} }"
fi
if (( ${+functions[precmd]} && ! ${+functions[_mascara_precmd_kali]} )) &&
   [[ ${functions[precmd]} != *_chuva_depois* ]]; then
  functions -c precmd _mascara_precmd_kali 2>/dev/null ||
    eval "_mascara_precmd_kali() { ${functions[precmd]} }"
fi

_mascara_original() { [[ -e ~/.mascara-cores-originais ]] }
_chuva_ligada() { [[ ! -e ~/.mascara-chuva-desligada ]] }

_mascara_desenho() {
  emulate -L zsh
  local E=$'\e[' Z=$'\e[0m' escuro claro vivo alerta arq titulo troca
  if _mascara_original; then
    escuro=245 vivo=39 claro=255 alerta=203 arq=$_MASCARA_DIR/mascara-real.ans titulo='V  //  M Á S C A R A' troca='cores verde'
    (( EUID == 0 )) && alerta=196 arq=$_MASCARA_DIR/mascara-real-root.ans
  elif (( EUID == 0 )); then
    escuro=22 vivo=46 claro=157 alerta=196 arq=$_MASCARA_DIR/mascara-root.ans troca='cores original'
  else
    escuro=28 vivo=46 claro=157 alerta=83 arq=$_MASCARA_DIR/mascara-kali.ans troca='cores original'
    titulo='V  //  M Á S C A R A   V E R D E'
  fi
  [[ -r $arq ]] || arq=$_MASCARA_DIR/mascara-kali.ans
  local L="${E}38;5;${escuro}m" V="${E}38;5;${claro}m" B="${E}1;38;5;${vivo}m" A="${E}1;38;5;${alerta}m"
  local -a arte info redes
  [[ -r $arq ]] && arte=("${(@f)$(<$arq)}")

  local seg=$(</proc/uptime) ligado
  seg=${seg%%.*}
  if (( seg >= 3600 )); then ligado="$(( seg / 3600 )) h $(( seg % 3600 / 60 )) min"; else ligado="$(( seg / 60 )) min"; fi
  local sistema=$(. /etc/os-release 2>/dev/null; print -r -- "${PRETTY_NAME:-Linux}")
  local memoria=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{if(t) printf "%.1f / %.1f GiB", (t-a)/1048576, t/1048576}' /proc/meminfo 2>/dev/null)
  local disco=$(df -h / 2>/dev/null | awk 'NR==2{print $3" / "$2" ("$5")"}')
  local nome estado end resto
  ip -4 -br addr 2>/dev/null | while read -r nome estado end resto; do
    [[ $nome == lo ]] && continue
    redes+=("${nome%%@*}|${end%%/*}")
  done

  local linha="${L}────────────────────────────────────────${Z}"
  if (( EUID == 0 )); then
    info+=("${A}☠  R O O T  ☠${Z}  ${L}poder total: cuidado${Z}")
  else
    info+=("${B}${titulo}${Z}")
  fi
  info+=("$linha")
  info+=("${L}usuário  ${V}${USER:-$(id -un)}${L} @ ${V}${HOST}${Z}")
  info+=("${L}sistema  ${V}${sistema}${Z}")
  info+=("${L}núcleo   ${V}$(uname -r)${Z}")
  info+=("${L}ligado   ${V}${ligado}${Z}")
  [[ -n $memoria ]] && info+=("${L}memória  ${V}${memoria}${Z}")
  [[ -n $disco ]] && info+=("${L}disco    ${V}${disco}${Z}")
  local r
  for r in $redes; do info+=("${L}${(r:9:)${r%%|*}}${B}${r#*|}${Z}"); done
  (( ${#redes} )) || info+=("${L}rede     ${A}sem IP${Z}")
  info+=("$linha")
  info+=("${L}remember, remember the fifth of november${Z}")
  info+=("${V}ideias não morrem ${L}//${V} hackeie com ética${Z}")
  info+=("")
  if _chuva_ligada; then
    info+=("${L}chuva    ${B}ligada${L} · ${V}chuva${L} desliga · ${V}Alt+Enter${L} sem${Z}")
  else
    info+=("${L}chuva    ${V}desligada${L} · ${V}chuva${L} liga${Z}")
  fi
  info+=("${L}comandos ${V}matrix${L} · ${V}mascara${L} · ${V}${troca}${Z}")

  local larg=${COLUMNS:-80} i x off n vazio
  printf -v vazio '%38s' ''
  print
  if (( ${#arte} && larg >= 88 )); then
    off=$(( (${#arte} - ${#info}) / 2 )); (( off < 0 )) && off=0
    n=$(( ${#arte} > ${#info} + off ? ${#arte} : ${#info} + off ))
    for (( i = 1; i <= n; i++ )); do
      x=''; (( i > off )) && x=${info[i-off]}
      print -r -- "  ${arte[i]:-$vazio}   $x"
    done
  else
    if (( ${#arte} && larg >= 42 )); then for x in "${arte[@]}"; do print -r -- "  $x"; done; print; fi
    for x in "${info[@]}"; do print -r -- "  $x"; done
  fi
  print
}

mascara() {
  case $1 in
    desligar) : >| ~/.mascara-desligada && print 'desenho desligado ao abrir o terminal (volta com: mascara ligar)' ;;
    ligar)    rm -f ~/.mascara-desligada && print 'desenho ligado' ;;
    *)        _mascara_desenho ;;
  esac
}

# prompt verde (o do root tem caveira e # vermelhos). Ctrl+P continua alternando entre uma e duas linhas.
setopt prompt_subst
_mascara_prompt_verde() {
  local cor=28 nome='%B%F{46}%n' fim='%B%F{46}$'
  if (( EUID == 0 )); then cor=22 nome='%B%F{196}☠ %n' fim='%B%F{196}#'; fi
  case ${PROMPT_ALTERNATIVE:-twoline} in
    oneline)
      PROMPT="${nome}%b%F{$cor}㉿%B%F{83}%m%b%F{$cor}:%B%F{157}%~%b ${fim}%b%f "
      RPROMPT=$'%(?.. %F{196}%? %B✘%b%f)%(1j. %F{220}%j %B⚙%b%f.)' ;;
    *)
      PROMPT="%F{$cor}┌──\${VIRTUAL_ENV:+(\${VIRTUAL_ENV:t})─}(${nome}%b%F{$cor}㉿%F{83}%m%F{$cor})-[%B%F{157}%(6~.%-1~/…/%4~.%5~)%b%F{$cor}]"$'\n'"%F{$cor}└─${fim}%b%f "
      RPROMPT=$'%(?.. %F{196}%? %B✘%b%f)%(1j. %F{220}%j %B⚙%b%f.)' ;;
  esac
}
configure_prompt() {
  if ! _mascara_original; then
    _mascara_prompt_verde
  elif (( ${+functions[_mascara_prompt_kali]} )); then
    _mascara_prompt_kali
  fi
}

# prompt, cores da digitação, da sugestão automática e do man: verdes, ou as originais do Kali (~/.mascara-cores-originais)
_mascara_cores() {
  local v
  if _mascara_original; then
    PROMPT=${_MASCARA_ORIGINAL[PROMPT]} RPROMPT=${_MASCARA_ORIGINAL[RPROMPT]}
    configure_prompt
    (( ${+ZSH_HIGHLIGHT_STYLES} && ${#_MASCARA_ORIGINAL_HL} )) && ZSH_HIGHLIGHT_STYLES=("${(@kv)_MASCARA_ORIGINAL_HL}")
    for v in ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE GROFF_NO_SGR LESS_TERMCAP_{mb,md,me,so,se,us,ue}; do
      if (( ! ${+_MASCARA_ORIGINAL[$v]} )); then
        unset $v
      elif [[ $v == ZSH_* ]]; then
        typeset -g $v=${_MASCARA_ORIGINAL[$v]}
      else
        export $v=${_MASCARA_ORIGINAL[$v]}
      fi
    done
    return 0
  fi
  configure_prompt
  if (( ${+ZSH_HIGHLIGHT_STYLES} )); then
    ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=196,bold'
    ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=120,bold'
    ZSH_HIGHLIGHT_STYLES[alias]='fg=46,bold'
    ZSH_HIGHLIGHT_STYLES[builtin]='fg=83,bold'
    ZSH_HIGHLIGHT_STYLES[function]='fg=83,bold'
    ZSH_HIGHLIGHT_STYLES[command]='fg=46,bold'
    ZSH_HIGHLIGHT_STYLES[precommand]='fg=120,italic'
    ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=34,bold'
    ZSH_HIGHLIGHT_STYLES[path]='fg=157,underline'
    ZSH_HIGHLIGHT_STYLES[globbing]='fg=118,bold'
    ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=114'
    ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=114'
    ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=221'
    ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=221'
    ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=221'
    ZSH_HIGHLIGHT_STYLES[redirection]='fg=48,bold'
    ZSH_HIGHLIGHT_STYLES[comment]='fg=65,italic'
  fi
  typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=65'
  export GROFF_NO_SGR=1
  export LESS_TERMCAP_mb=$'\e[1;38;5;196m' LESS_TERMCAP_md=$'\e[1;38;5;46m' LESS_TERMCAP_me=$'\e[0m'
  export LESS_TERMCAP_so=$'\e[1;38;5;16;48;5;83m' LESS_TERMCAP_se=$'\e[0m'
  export LESS_TERMCAP_us=$'\e[4;38;5;157m' LESS_TERMCAP_ue=$'\e[0m'
}

# esquema de cores do QTerminal (vale para as abas e janelas novas; o QTerminal relê o arquivo sozinho)
_mascara_qterminal() {
  emulate -L zsh
  local ini=${XDG_CONFIG_HOME:-$HOME/.config}/qterminal.org/qterminal.ini
  [[ $1 =~ '^[A-Za-z0-9_. -]+$' && -f $ini && -w $ini ]] || return 1
  if grep -q '^colorScheme=' $ini; then
    sed -i "s/^colorScheme=.*/colorScheme=$1/" $ini
  else
    grep -q '^\[General\]' $ini || return 1
    sed -i "/^\[General\]/a colorScheme=$1" $ini
  fi
}

# papel de parede do XFCE, na hora, em todas as telas e áreas de trabalho (só o do kali; o root não tem área de trabalho)
_mascara_papel() {
  emulate -L zsh
  (( EUID && ${+commands[xfconf-query]} )) && [[ -r $1 && -n $DISPLAY ]] || return 1
  local p feito=1
  for p in ${(f)"$(xfconf-query -c xfce4-desktop -l 2>/dev/null)"}; do
    [[ $p == */last-image ]] || continue
    xfconf-query -c xfce4-desktop -p $p -s $1 2>/dev/null && feito=0
  done
  return $feito
}
_mascara_papel_original() {                          # o papel do tema nas cores originais; sem ele, o padrão do Kali
  local p=$_MASCARA_PAPEL_ORIGINAL
  [[ -r $p ]] || p=/usr/share/backgrounds/kali-16x9/default
  [[ -e $p ]] || p=$(sed -n 's/.*name="image-path"[^>]*value="\([^"]*\)".*/\1/p' \
                     /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml 2>/dev/null | head -n 1)
  print -r -- $p
}

# O QTerminal 2.4 não troca as cores de uma aba aberta: abre uma aba nova na mesma pasta (pelo D-Bus dele), já com
# o esquema novo, e fecha esta. Só quando nada roda nesta aba e o shell é o da própria aba.
_mascara_reabrir_aba() {
  emulate -L zsh
  (( ${#jobstates} == 0 && ${+commands[gdbus]} )) || return 1
  [[ $(ps -o comm= -p $PPID 2>/dev/null) == qterminal ]] || return 1
  local servico=org.lxqt.QTerminal-$PPID resposta janela dir=${${PWD//\\/\\\\}//\'/\\\'}
  resposta=$(gdbus call --session --timeout 3 --dest $servico --object-path / \
             --method org.lxqt.QTerminal.Process.getActiveWindow 2>/dev/null) || return 1
  janela=${${resposta#*\'}%%\'*}
  [[ $janela == /* ]] || return 1
  resposta=$(gdbus call --session --timeout 3 --dest $servico --object-path $janela \
             --method org.lxqt.QTerminal.Window.newTab "{'workingDirectory': <'$dir'>}" 2>/dev/null) || return 1
  [[ $resposta == *objectpath* ]] || return 1
  exit
}

cores() {
  emulate -L zsh
  local marca=~/.mascara-cores-originais esquema papel nome
  case ${1:-} in
    original|originais|kali)
      : >| $marca
      esquema=$(sed -n 's/^colorScheme=//p' /etc/xdg/qterminal.org/qterminal.ini 2>/dev/null | head -n 1)
      [[ -n $esquema && $esquema != Mascara* ]] || esquema=Kali-Dark
      papel=$(_mascara_papel_original) nome='cores originais do Kali' ;;
    verde|mascara)
      rm -f -- $marca
      if (( EUID == 0 )); then esquema=MascaraRoot; else esquema=Mascara; fi
      papel=$_MASCARA_PAPEL_VERDE nome='tema Máscara verde' ;;
    '')
      if _mascara_original; then
        print 'agora: cores originais do Kali   (voltar ao tema: cores verde)'
      else
        print 'agora: tema Máscara verde   (cores do Kali: cores original)'
      fi
      return 0 ;;
    *)
      print -u2 'uso: cores original | cores verde'
      return 2 ;;
  esac
  _mascara_cores
  local ok_papel=0 ok_qt=0
  [[ -n $papel ]] && _mascara_papel $papel && ok_papel=1
  _mascara_qterminal $esquema && ok_qt=1
  (( ok_qt )) && _mascara_reabrir_aba                   # não volta daqui: a aba nova assume
  _mascara_desenho
  print -n -- "${nome}: prompt, digitação, man e máscara"
  (( ok_papel )) && print -n ', papel de parede'
  print '.'
  if (( ok_qt )); then
    print "Fundo e letras ($esquema): só nas abas novas (Ctrl+Shift+T); não deu para trocar esta aba sozinho."
  else
    print 'Não achei a configuração do QTerminal: o fundo e as letras do terminal ficaram como estavam.'
  fi
}

# ---------------------------------------------------------------- chuva de código nos resultados
# Ligada (padrão; "chuva" desliga e liga, fica salvo em ~/.mascara-chuva-desligada): antes de cada comando o zsh liga
# a saída dele a um terminal falso criado pelo "matrix --capturar" (o comando continua vendo um terminal: mesmas
# cores e colunas) e, quando ele acaba, o resultado cai na chuva. Programas de tela cheia, shells e comandos que mexem
# no próprio shell rodam normais (lista abaixo); qualquer linha: Alt+Enter roda ao contrário.
typeset -ga _CHUVA_FORA=(
  vi vim nvim vimdiff view nano pico emacs less more most man info pinfo top htop btop atop iotop iftop nethogs watch
  tmux screen ssh telnet ftp sftp ncftp nc ncat netcat socat rlwrap msfconsole msfdb mysql mariadb psql sqlite3
  redis-cli mongosh gdb r2 radare2 su login passwd chsh chfn exec exit logout clear reset tput stty cd pushd popd
  source . fg bg jobs wait disown read vared fc matrix chuva cores mascara apt apt-get aptitude dpkg docker podman git
  crontab visudo vipw sudoedit nmtui alsamixer mc ranger nnn lynx w3m elinks links tig wifite airodump-ng airmon-ng
  kismet bettercap mitmproxy ettercap minicom setsid nohup
)
typeset -ga _CHUVA_FORA_SEM_ARGS=(python python2 python3 ipython ipython3 irb node php lua perl ruby bash zsh sh dash fish bc)
typeset -ga _CHUVA_PAGINADORES=(PAGER SYSTEMD_PAGER GIT_PAGER MANPAGER)
typeset -gA _CHUVA_PAG_ANTES

# a linha tem de rodar sem a chuva? (tela cheia, shell interativo, segundo plano, comando que mexe no próprio shell)
_chuva_fora() {
  emulate -L zsh
  setopt extended_glob
  local -a w=(${(z)1}) apelido
  local i=1 n=${#w} t cmd nargs segue
  for t in $w; do [[ $t == ('&'|'&!'|'&|') ]] && return 0; done
  while (( i <= n )); do
    while (( i <= n )); do                              # atribuições e prefixos (sudo, env, time...)
      t=${w[i]}
      if [[ $t == [[:alpha:]_][[:alnum:]_]#=* ]]; then (( i++ )); continue; fi
      case $t in
        (sudo|doas)
          (( i++ ))
          while (( i <= n )) && [[ ${w[i]} == -* ]]; do
            [[ ${w[i]} == (-u|-g|-C|-D|-h|-p|-r|-t|-U|-T|--user|--group|--chdir|--prompt|--role|--type|--host|--other-user|--close-from|--command-timeout) ]] && (( i++ ))
            (( i++ ))
          done ;;
        (env|nice|ionice|time|command|builtin|noglob|nocorrect|proxychains|proxychains4|torsocks|stdbuf|timeout|unbuffer)
          (( i++ ))
          while (( i <= n )) && [[ ${w[i]} == (-*|[[:alpha:]_][[:alnum:]_]#=*) ]]; do (( i++ )); done
          [[ $t == timeout && ${w[i]} == [0-9]* ]] && (( i++ )) ;;
        (*) break ;;
      esac
    done
    (( i > n )) && return 0                             # sudo -i, sudo -s... abrem um shell
    cmd=${w[i]}
    if (( ${+aliases[$cmd]} )); then                    # ${${(z)x}[1]} daria a 1ª letra se o apelido tiver 1 palavra
      apelido=(${(z)aliases[$cmd]})
      cmd=${apelido[1]}
    fi
    cmd=${cmd:t}
    (( ${_CHUVA_FORA[(Ie)$cmd]} )) && return 0
    nargs=0 segue=0
    for (( i++; i <= n; i++ )); do
      t=${w[i]}
      if [[ $t == ('|'|'||'|'&&'|';'|'|&') ]]; then (( i++ )); break; fi
      [[ $t == -* ]] || (( nargs++ ))
      [[ $t == (-f|-F|--follow*|-w) ]] && segue=1
    done
    (( nargs == 0 && ${_CHUVA_FORA_SEM_ARGS[(Ie)$cmd]} )) && return 0
    [[ $cmd == (tail|journalctl|dmesg) ]] && (( segue )) && return 0
  done
  return 1
}

# os paginadores viram cat enquanto a saída vai para o terminal falso (um less ali ficaria invisível)
_chuva_paginadores() {
  local v
  if [[ -n $1 ]]; then
    _CHUVA_PAG_ANTES=()
    for v in $_CHUVA_PAGINADORES; do
      [[ -v $v ]] && _CHUVA_PAG_ANTES[$v]=${(P)v}
      export $v=$1
    done
  else
    for v in $_CHUVA_PAGINADORES; do
      if (( ${+_CHUVA_PAG_ANTES[$v]} )); then export $v=${_CHUVA_PAG_ANTES[$v]}; else unset $v; fi
    done
  fi
}

# começa o "matrix --capturar": o terminal falso fica em $_CHUVA_PTS e os arquivos em $_CHUVA_BASE.*
_chuva_abrir() {
  emulate -L zsh
  local dir=${XDG_RUNTIME_DIR:-} i
  if [[ -z $dir || ! -d $dir || ! -w $dir || ! -O $dir ]]; then
    [[ -n $_CHUVA_TMP && -d $_CHUVA_TMP ]] || typeset -g _CHUVA_TMP=$(mktemp -d "${TMPDIR:-/tmp}/chuva.XXXXXX" 2>/dev/null)
    dir=$_CHUVA_TMP
  fi
  [[ -n $dir && -d $dir ]] || return 1
  typeset -g _CHUVA_BASE=$dir/chuva.$$ _CHUVA_PTS=
  rm -f -- $_CHUVA_BASE.{pty,fim,saida}{,.tmp}
  matrix --capturar $_CHUVA_BASE </dev/null 2>/dev/null &!
  for (( i = 0; i < 100; i++ )); do
    [[ -s $_CHUVA_BASE.pty ]] && break
    _chuva_pausa
  done
  [[ -s $_CHUVA_BASE.pty ]] && _CHUVA_PTS=$(<$_CHUVA_BASE.pty)
  if [[ $_CHUVA_PTS != /dev/pts/<-> || ! -w $_CHUVA_PTS ]]; then
    : >| $_CHUVA_BASE.fim 2>/dev/null                   # se o ajudante ainda subir, ele sai sozinho
    unset _CHUVA_BASE _CHUVA_PTS
    return 1
  fi
}

# preexec: a saída do comando vai para o terminal falso
_chuva_antes() {
  local inverte=$_CHUVA_INVERTE
  _CHUVA_INVERTE=
  (( ${+_CHUVA_BASE} )) || [[ ! -t 1 ]] && return 0
  local -a w=(${(z)1})
  if [[ ${w[1]} == chuva && -n ${w[2]} && ${w[2]} != (ligar|desligar|on|off) ]]; then
    _chuva_fora "${(j: :)w[2,-1]}" && return 0          # chuva <comando>: com a chuva mesmo desligada
  else
    if [[ -n $inverte ]]; then _chuva_ligada && return 0; else _chuva_ligada || return 0; fi
    _chuva_fora "$1" && return 0
  fi
  _chuva_abrir || return 0
  typeset -g _CHUVA_SAIDA _CHUVA_ERRO
  exec {_CHUVA_SAIDA}>&1 {_CHUVA_ERRO}>&2
  exec >$_CHUVA_PTS 2>&1
  _chuva_paginadores cat
}

# precmd (antes do precmd do Kali): devolve o terminal, avisa o ajudante e faz a chuva com o que o comando escreveu
_chuva_depois() {
  (( ${+_CHUVA_BASE} )) || return 0
  local base=$_CHUVA_BASE i
  unset _CHUVA_BASE _CHUVA_PTS
  if (( ${+_CHUVA_SAIDA} )); then
    exec 1>&$_CHUVA_SAIDA 2>&$_CHUVA_ERRO {_CHUVA_SAIDA}>&- {_CHUVA_ERRO}>&-
    unset _CHUVA_SAIDA _CHUVA_ERRO
    _chuva_paginadores
  fi
  : >| $base.fim
  for (( i = 0; i < 300; i++ )); do
    [[ -e $base.saida ]] && break
    _chuva_pausa
  done
  [[ -s $base.saida ]] && matrix < $base.saida
  rm -f -- $base.{pty,fim,saida}
}

_chuva_pausa() {                                        # 1 centésimo de segundo
  if (( ${+builtins[zselect]} )); then zselect -t 1; else sleep 0.01; fi
  return 0
}

precmd() {
  _chuva_depois
  (( ${+functions[_mascara_precmd_kali]} )) && _mascara_precmd_kali "$@"
}
(( ${preexec_functions[(Ie)_chuva_antes]} )) || preexec_functions+=(_chuva_antes)
_chuva_sair() { [[ -n $_CHUVA_TMP ]] && rm -rf -- $_CHUVA_TMP }
(( ${zshexit_functions[(Ie)_chuva_sair]} )) || zshexit_functions+=(_chuva_sair)

# chuva: liga e desliga | chuva ligar | chuva desligar | chuva <comando>: só este comando com a chuva
function chuva {
  case ${1-} in
    ('')
      if _chuva_ligada; then chuva desligar; else chuva ligar; fi
      return ;;
    (ligar|on)
      rm -f ~/.mascara-chuva-desligada
      print 'chuva ligada: o resultado de cada comando cai na chuva  (desligar: chuva · uma linha sem: Alt+Enter)'
      return 0 ;;
    (desligar|off)
      : >| ~/.mascara-chuva-desligada
      print 'chuva desligada  (ligar: chuva · uma linha com: Alt+Enter ou chuva <comando>)'
      return 0 ;;
  esac
  if (( ${+_CHUVA_SAIDA} )); then                       # a linha já está indo para o terminal falso (preexec)
    "$@"
    return
  fi
  if _chuva_fora "$*"; then
    print -u2 "chuva: $1 é interativo; vai sem a chuva"
    "$@"
    return
  fi
  "$@" 2>&1 | matrix                                    # sem o terminal falso: pelo cano (sem as cores do comando)
  return ${pipestatus[1]}
}
alias chuva='chuva '   # o espaço deixa os apelidos funcionarem depois do chuva (chuva ll)

# Alt+Enter: esta linha ao contrário (sem a chuva quando ela está ligada, com a chuva quando está desligada)
_mascara_chuva_enter() {
  typeset -g _CHUVA_INVERTE=1
  zle accept-line
}
zle -N _mascara_chuva_enter
bindkey '^[^M' _mascara_chuva_enter

_mascara_cores
[[ -e ~/.mascara-desligada || -n $MASCARA_JA_MOSTRADA ]] || _mascara_desenho
export MASCARA_JA_MOSTRADA=1
