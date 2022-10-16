#!/usr/bin/env bash

ENVCTL_PATH=${BASH_SOURCE[0]}
ENVCTL_LAUNCHD_NAME="envctl.conf.launchd"
ENVCTL_PLIST_PATH="$HOME/Library/LaunchAgents/$ENVCTL_LAUNCHD_NAME.plist"
ENVCTL_CONFIG_PATH="$HOME/.config/envctl.conf"

if [[ ! -f $ENVCTL_CONFIG_PATH ]]; then
  touch "$ENVCTL_CONFIG_PATH"
fi

__echo_red() {
  echo -e "\033[1;31m$1\033[0m"
}

__echo_green() {
  echo -e "\033[1;32m$1\033[0m"
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
    if [[ -z $launchValue ]]; then
      __echo_green "$k=$v (Not launchd)"
    elif [ "$v" == "$launchValue" ]; then
      __echo_green "$k=$v"
    else
      __echo_green "$k=$v (Why launchd: $launchValue)"
    fi
  done <"${ENVCTL_CONFIG_PATH}"
}

__envctl_get() {
  local key=$1
  if [[ -z $key ]]; then
    __echo_red "Usage: envl get <key>"
    exit 1
  fi

  value=""
  while IFS='=' read -r k v; do
    if [[ $k == "$key" ]]; then
      value=$v
      break
    fi
  done <"${ENVCTL_CONFIG_PATH}"
  launchValue=$(launchctl getenv "$key")

  if [[ -z $launchValue ]]; then
    if [[ -n $value ]]; then
      __echo_green "$value (Not Launchd)"
    else
      __echo_red "No variable"
    fi
  else
    if [[ -z $value ]]; then
      __echo_red "$launchValue (Not managed)"
    elif [ "$value" != "$launchValue" ]; then
      __echo_red "$value (Why launchd: $launchValue)"
    else
      __echo_green "$value"
    fi
  fi
}

__envctl_unset() {
  local key=$1
  if [[ -z $key ]]; then
    __echo_red "Usage: envctl unset <key>"
    exit 1
  fi

  line=$(grep "$key=" "$ENVCTL_CONFIG_PATH")
  if [[ -n $line ]]; then
    launchctl unsetenv "$key"
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

  oldValue=""
  replace=1
  while IFS='=' read -r k v; do
    if [[ $k == "$key" ]]; then
      oldValue=$v
      break
    fi
  done <"${ENVCTL_CONFIG_PATH}"
  if [[ -z $oldValue ]]; then
    oldValue=$(launchctl getenv "$key")
    replace=0
  fi

  if [[ -n $oldValue && $oldValue != "$value" ]]; then
    read -r -n 1 -t 30 -p "Please make sure set '$key' from '$oldValue' to '$value': 'Y/n'" j
    echo ""
    if [[ $j != "Y" ]]; then
      __echo_red "Not replace $key=$value"
      exit 1
    fi
  fi

  if [[ $replace == 1 ]]; then
    sed -i "" "s# $key=.*# $key=$value#g" "$ENVCTL_CONFIG_PATH"
  else
    echo "$key=$value" >>"$ENVCTL_CONFIG_PATH"
  fi

  result=$(launchctl setenv "$key" "$value")
  if [[ ! $result ]]; then
    __echo_green "Set $key=$value"
  else
    if [[ $replace == 1 ]]; then
      sed -i "" "s#$key=.*#$key=$oldValue#g" "$ENVCTL_CONFIG_PATH"
    else
      sed -i "" "/$key=/d" "$ENVCTL_CONFIG_PATH"
    fi
    __echo_red "Set $key failed"
    exit 1
  fi
}

__envctl_load() {
  while IFS='=' read -r k v; do
    launchValue=$(launchctl getenv "$k")
    launchctl setenv "$k" "$v"
    if [[ -z $launchValue ]]; then
      __echo_green "$k=$v"
    elif [ "$v" == "$launchValue" ]; then
      __echo_green "$k=$v"
    else
      __echo_green "$k=$launchValue => $k=v"
    fi
  done <"${ENVCTL_CONFIG_PATH}"
}

__envctl_unload() {
  while IFS='=' read -r k v; do
    launchctl unsetenv "$k"
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

__envctl_parse_args "$@"
