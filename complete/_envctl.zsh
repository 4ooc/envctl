#compdef envctl

typeset -a commands
commands=(
  set:'set env [key] [value]'
  get:'get env [key]'
  unset:'unset env [key]'
  list:'List all environment variables'
  activate:'Set all env var and activate plist'
  inactivate:'Unset all env var and activate plist'
)

_arguments -C \
  '1: :->command' \
  '2: :->argument' && ret=0

case $state in
command)
  _describe -t commands "envctl command" commands && ret=0
  ;;

argument)
  case $words[2] in
  set | get | unset)
    typeset -a keys

    while IFS='=' read -r k _; do
      keys+=("$k")
    done <"$HOME/.config/envctl.conf"

    compadd "$@" -a - keys &&
      ret=0
    ;;
  *)
    ret=1
    ;;
  esac
  ;;
esac

return $ret
