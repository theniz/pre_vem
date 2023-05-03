set -uo pipefail

__non_interactive=0
if echo "$@" | grep -q '.*--non-interactive.*' 2>/dev/null ; then
  __non_interactive=1
fi

if [ ${__non_interactive} = 1 ]; then
    __password="${KEYSTORE_PASSWORD}"
    __justone=1
else
    __num_files=$(find validator_keys -maxdepth 1 -type f -name 'keystore*.json' | wc -l)
    if [ "$__num_files" -eq 0 ]; then
        echo "No keystore*.json files found in vem/validator_keys/"
        echo "Nothing to do"
        exit 0
    fi

    if [ "$__num_files" -gt 1 ]; then
        while true; do
            read -rp "Do all validator keys have the same password? (y/n) " yn
            case $yn in
                [Yy]* ) __justone=1; break;;
                [Nn]* ) __justone=0; break;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    else
        __justone=1
    fi

    if [ "${__justone}" -eq 1 ]; then
        while true; do
            read -srp "Please enter the password for your validator key(s): " __password
            echo
            read -srp "Please re-enter the password: " __password2
            echo
            if [ "${__password}" == "${__password2}" ]; then
                break
            else
                echo "The two entered passwords do not match, please try again."
                echo
            fi
        done
        echo
    fi
fi

created=0
failed=0
mkdir -p exit_messages
for __keyfile in validator_keys/keystore-*.json; do
    [ -f "${__keyfile}" ] || continue
    if [ "${__justone}" -eq 0 ]; then
        while true; do
            read -srp "Please enter the password for your validator key stored in ${__keyfile}: " __password
            echo
            read -srp "Please re-enter the password: " __password2
            echo
            if [ "${__password}" == "${__password2}" ]; then
                break
            else
                echo "The two entered passwords do not match, please try again."
                echo
            fi
            echo
        done
    fi

    __pubkey="$(sed -E 's/.*"pubkey":\s*"([0-9a-fA-F]+)".*/\1/' < "${__keyfile}")"
    if [ -z "$__pubkey" ]; then
        echo "Unable to read public key from ${__keyfile}. Is it the right format?"
        continue
    else
        __pubkey="0x${__pubkey}"
    fi

    __json=$(./ethdo validator exit --validator "${__keyfile}" --json --timeout 2m --passphrase "${__password}" --offline)
    exitstatus=$?
    if [ "${exitstatus}" -eq 0 ]; then
      echo "${__json}" >"exit_messages/${__pubkey::10}--${__pubkey:88:10}-exit.json"
      exitstatus=$?
      if [ "${exitstatus}" -eq 0 ]; then
        echo "Creating an exit message for validator ${__pubkey} into file ./exit_messages/${__pubkey::10}--${__pubkey:88:10}-exit.json succeeded"
        (( created++ ))
      else
        echo "Error writing exit json to file ./exit_messages/${__pubkey::10}--${__pubkey:88:10}-exit.json"
        (( failed++ ))
      fi
    else
      echo "Creating an exit message for validator ${__pubkey} from file ${__keyfile} failed"
      (( failed++ ))
    fi
done

echo
echo "Created pre-signed voluntary exit messages for ${created} validators"

if [ "${created}" -gt 0 ]; then
  cd ./exit_messages
  jq -s '.' *.json > all-validators-exit-operations.json
  for ((i=0; i<`jq -ec '.|length' all-validators-exit-operations.json`;i++)); do validator=`jq -ec ".[${i}].message.validator_index|tonumber" all-validators-exit-operations.json`; echo "`jq -ec ".[${i}]" all-validators-exit-operations.json`" > "validator_index-"${validator}-exit.json;done
  cd ..
  echo
  echo "There are also 1 exit file for all validators and ${created} validator_index exit files"
  echo "Pubkey file and validator_index file are the same one. Use it according to your choice !!" 
  echo
  echo "You can find them in ./exit_messages"
  echo
fi

if [ "${failed}" -gt 0 ]; then
  echo "Failed for ${failed} validators"
fi
