#!/usr/bin/env bash

ENVCTL_PATH=${BASH_SOURCE[0]}
ENVCTL_LAUNCHD_NAME="envctl.conf.launchd"
ENVCTL_PLIST_PATH="$HOME/Library/LaunchAgents/$ENVCTL_LAUNCHD_NAME.plist"
ENVCTL_CONFIG_PATH="$HOME/.config/envctl.conf"

__create_config_if_not_exist() {
  if [[ ! -f $ENVCTL_CONFIG_PATH ]]; then
    touch "$ENVCTL_CONFIG_PATH"
  fi
}

__echo_red() {
  echo -e "\033[1;31m$1\033[0m"
}

__echo_green() {
  echo -e "\033[1;32m$1\033[0m"
}

__envctl_match_key() {
  configs=$(cat "$ENVCTL_CONFIG_PATH")
  [[ $configs =~ $1=(.*) ]]
  echo "${BASH_REMATCH[1]}"
}

__envctl_key_print() {
  configValue=$1
  launchValue=$2
  key=$3

  if [[ -n $launchValue ]]; then
    if [[ -z $configValue ]]; then
      __echo_red "$key  (Unknown override: $launchValue)"
    elif [ "$configValue" != "$launchValue" ]; then
      __echo_red "$key  $configValue (Unknown override: $launchValue)"
    else
      __echo_green "$key  $configValue"
    fi
  else
    if [[ -z $configValue ]]; then
      __echo_red "No variable"
    else
      __echo_green "$key  $configValue (Not Launchd)"
    fi
  fi
}

__envctl_update_plist() {
  cat >"${ENVCTL_PLIST_PATH}" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>envctl.conf.launchd</string>
      <key>ProgramArguments</key>
      <array>
        <string>bash</string>
        <string>-l</string>
        <string>-c</string>
        <string>${ENVCTL_PATH} load</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
    </dict>
    </plist>
EOF
}

__envctl_remove_service() {
  launchctl remove "$ENVCTL_LAUNCHD_NAME"
}

__envctl_load_service() {
  __envctl_remove_service
  launchctl load "$ENVCTL_PLIST_PATH"
}

__envctl_list() {
  while IFS='=' read -r k v; do
    launchValue=$(launchctl getenv "$k")
    __envctl_key_print "$v" "$launchValue" "$k"
  done <"${ENVCTL_CONFIG_PATH}"
}

__envctl_get() {
  local key=$1
  if [[ -z $key ]]; then
    __echo_red "Usage: envl get <key>"
    exit 1
  fi

  configValue=$(__envctl_match_key "$key")
  launchValue=$(launchctl getenv "$key")

  __envctl_key_print "$configValue" "$launchValue"
}

__envctl_unset() {
  local key=$1
  if [[ -z $key ]]; then
    __echo_red "Usage: envctl unset <key>"
    exit 1
  fi

  launchctl unsetenv "$key"
  value=$(__envctl_match_key "$key")
  if [[ -n $value ]]; then
    sed -i "" "/$key=/d" "$ENVCTL_CONFIG_PATH"
  fi
}

__envctl_set() {
  local key=$1
  local value=$2
  if [[ -z $key || -z $value ]]; then
    __echo_red "Usage: envctl set <key> <value>"
    exit 1
  fi

  replace=1
  oldValue=$(__envctl_match_key "$key")
  if [[ -z $oldValue ]]; then
    oldValue=$(launchctl getenv "$key")
    replace=0
  fi

  if [[ -n $oldValue && $oldValue != "$value" ]]; then
    read -r -n 1 -t 30 -p "Continue set '$key' from '$oldValue' to '$value': 'Y/n'" j
    echo ""
    if [[ $j != "Y" ]]; then
      __echo_red "Not replace $key=$value"
      exit 1
    fi
  fi

  launchctl setenv "$key" "$value"
  if [[ $replace == 1 ]]; then
    sed -i "" "s# $key=.*# $key=$value#g" "$ENVCTL_CONFIG_PATH"
  else
    echo "$key=$value" >>"$ENVCTL_CONFIG_PATH"
  fi
  __echo_green "Set $key=$value"
}

__envctl_load() {
  __echo_green "Load env:"
  while IFS='=' read -r k v; do
    launchValue=$(launchctl getenv "$k")
    launchctl setenv "$k" "$v"
    if [[ -z $launchValue ]]; then
      __echo_green "    $k=$v"
    elif [ "$v" == "$launchValue" ]; then
      __echo_green "    $k=$v"
    else
      __echo_green "    $k=$launchValue => $k=v"
    fi
  done <"${ENVCTL_CONFIG_PATH}"
}

__envctl_unload() {
  __echo_green "Unload env:"
  while IFS='=' read -r k v; do
    launchctl unsetenv "$k"
    __echo_green "    $k=$v"
  done <"${ENVCTL_CONFIG_PATH}"
}

__envctl_activate() {
  __envctl_update_plist
  __envctl_load_service
  __envctl_load
}

__envctl_inactivate() {
  __envctl_remove_service
  __envctl_unload
}

__envctl_help() {
  cat <<EOF
  Set environment variables for GUI applications.
  <set|get|unset> would active command <start>.
  Subcommands:
    set	          Set env
    get	          Get env
    unset         Unset env
    list          List all environment variables
    activate      Set all env var and activate service
    inactivate    Unset all env var and inactivate service
EOF
  exit 0
}

__envctl_parse_args() {
  if command -v __envctl_"$1" > /dev/null; then
    __envctl_"$1" "$2" "$3"
  else
    __envctl_help
  fi
}

__create_config_if_not_exist
__envctl_parse_args "$@"
