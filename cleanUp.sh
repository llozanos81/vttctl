#!/usr/bin/env bash
ENV_FILE=.env
if [ -f ${ENV_FILE} ]; then
  export $(cat .env | xargs)
fi

DIR_VERSIONS=$(ls -l FoundryVTT/ | grep "^d" | awk '{print $NF}' | grep "^[0-9]*")
IMG_VERSIONS=$(docker images -a | grep vtt | awk {'print $1":"$2'})
BIN_VERSIONS=$(ls downloads/ | grep -E '[0-9]{2,3}\.[0-9]{2,3}')

declare -A word_counts

# Loop through each variable
for var_name in DIR_VERSIONS IMG_VERSIONS BIN_VERSIONS; do
  var_value=${!var_name}  # Get the value of the variable using indirect expansion
  word_count=$(echo "$var_value" | wc -w)
  word_counts[$var_name]=$word_count
done

# Find the variable with the maximum word count
max_words=0
max_variable=""
for var_name in "${!word_counts[@]}"; do
  if (( word_counts[$var_name] > max_words )); then
    max_words=${word_counts[$var_name]}
    max_variable=$var_name
  fi
done

BIGGEST=${!max_variable}

pattern="[0-9]{1,3}\.[0-9]{1,3}"

count=1
echo "Default version $DEFAULT_VER"
while [[ $OPT != "0" ]]; do
  list=()
  echo "Choose version to clean/delete ('0' to cancel):"
  for i in $BIGGEST; do
    [[ $i =~ $pattern ]] && version="${BASH_REMATCH[0]}"
    if [ ! $version == $DEFAULT_VER ]; then
      list+=($version)
      echo "$count) $version"
      ((count++))
    fi
  done
  read -p "Version to clean/delete?: " OPT

  if [[ $OPT =~ ^[0-9]+$ && $OPT -ge 1 && $OPT -le $count ]]; then
    ((OPT--))
    DEL_VER=${list[$OPT]}
    read -p "Are you sure you want to remove all v$DEL_VER related assets? (y/n): " confirmation
    if [ "$confirmation" == "y" ] || [ "$confirmation" == "Y" ]; then
      echo "Deleting zip file ..."
      rm -f downloads/*$DEL_VER*
      echo "Deleting extracted folder ..."
      rm -rf FoundryVTT/$DEL_VER/
      echo "Deleting Docker image ..."
      docker images rmi foundryvtt:$DEL_VER
      echo "Cleaning completed."
    else
      echo "Cleaning cancelled."
      exit
    fi
    break
  elif [[ $OPT != "0" ]]; then
    echo "Invalid option."
  fi
done