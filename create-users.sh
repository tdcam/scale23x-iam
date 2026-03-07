#!/bin/bash

INPUT_FILE="user_list.txt"
GROUP_NAME="beetles"
DEFAULT_PW="red22hat

# Ensure the group exists
ipa group-show "$GROUP_NAME" > /dev/null 2>&1 || ipa group-add "$GROUP_NAME"

while IFS= read -r full_name || [[ -n "$full_name" ]]; do
    [[ -z "$full_name" ]] && continue

    first_name=$(echo "$full_name" | awk '{print $1}')
    last_name=$(echo "$full_name" | awk '{print $2}')
    username=$(echo "${first_name}.${last_name}" | tr '[:upper:]' '[:lower:]')

    echo "Creating user: $username..."

    # Use echo to feed the password into the command twice
    # (Once for the password, once for the confirmation)
    echo "$DEFAULT_PW" | ipa user-add "$username" \
        --first="$first_name" \
        --last="$last_name" \
        --displayname="$full_name" \
        --gecos="$full_name" \
        --homedir="/home/$username" \
        --shell="/bin/bash" \
        --password > /dev/null 2>&1

    # Add to group
    ipa group-add-member "$GROUP_NAME" --users="$username" > /dev/null 2>&1

done < "$INPUT_FILE"

echo "Done! All users created with the default password: $DEFAULT_PW"
