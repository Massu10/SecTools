# >>> caveira (personalização 25/10/2026) >>>
if [[ $- == *i* ]]; then
  print -P '%F{250}'
  cat <<'ARTE'
            _.-''''''-._
          .'  _      _  '.
         /   (_)    (_)   \
        |  ,   .----.   ,  |
        |   '-.______.-'   |
         \   ~~~~\  /~~~~  /
          \       \/      /
           '.     ||    .'
             '-.__||__.-'
ARTE
  print -P '%F{124}     we are anonymous  //  expect us%f'
  ip -4 -br addr 2>/dev/null | grep -v '^lo' | awk '{printf "\033[38;5;240m     %-8s %s\033[0m\n", $1, $3}'
  echo
fi
PROMPT=$'%F{238}┌──%F{244}[%F{160}%n%F{244}@%F{250}%m%F{244}]%F{238}─%F{244}[%F{246}%~%F{244}]\n%F{238}└─%F{160}$%f '
# <<< caveira <<<
