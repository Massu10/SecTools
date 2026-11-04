# >>> caveira root (personalização 25/10/2026) >>>
if [[ $- == *i* ]]; then
  print -P '%F{88}'
  cat <<'ARTE'
            _.-''''''-._
          .'  _      _  '.
         /   (X)    (X)   \
        |  ,   .----.   ,  |
        |   '-.______.-'   |
         \   ~~~~\  /~~~~  /
          \       \/      /
           '.     ||    .'
             '-.__||__.-'
ARTE
  print -P '%F{52}   ═══════════════════════════════'
  print -P '%F{196}%B        ☠  R O O T  ☠%b'
  print -P '%F{52}   ═══════════════════════════════%f'
  print -P '%F{240}   we do not forgive // we do not forget%f'
  ip -4 -br addr 2>/dev/null | grep -v '^lo' | awk '{printf "\033[38;5;238m   %-8s %s\033[0m\n", $1, $3}'
  echo
fi
PROMPT=$'%F{52}┌──%F{88}[%F{196}☠ %B%n%b%F{88}@%F{124}%m%F{88}]%F{52}─%F{88}[%F{244}%~%F{88}]\n%F{52}└─%F{196}%B#%b%f '
# <<< caveira root <<<
