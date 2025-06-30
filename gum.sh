#!/bin/bash

# Check for dialog
if ! command -v dialog &>/dev/null; then
    echo "dialog is not installed. Run: sudo apt install dialog"
    exit 1
fi

# Temp files
TMPFILE=$(mktemp)
SEARCHFILE=$(mktemp)


# Step 1: Build list of default per-user groups (same name and GID)
declare -A user_primary_gids
while IFS=: read -r username _ _ gid _ home _; do
    if [[ "$home" == /home/* ]]; then
        user_primary_gids["$username"]=$gid
    fi
done < /etc/passwd

declare -A default_user_groups
while IFS=: read -r group_name _ gid members; do
    if [[ -n "${user_primary_gids[$group_name]}" && "${user_primary_gids[$group_name]}" -eq "$gid" ]]; then
        default_user_groups["$group_name"]=1
    fi
done < /etc/group

# Step 2: Define known system group names
SYSTEM_GROUPS_BY_NAME=(
    root daemon bin sys adm tty disk lp mail news uucp man
    proxy www-data backup list irc gnats nobody nogroup
    systemd-journal systemd-network systemd-resolve systemd-timesync
    messagebus syslog
)
system_group_pattern="^($(IFS=\|; echo "${SYSTEM_GROUPS_BY_NAME[*]}"))$"

# === Main loop ===
while true; do
  dialog --clear \
    --backtitle "Group Manager" \
    --title "Main Menu" \
    --menu "Choose an action:" 15 60 5 \
    1 "Search group" \
    2 "Browse all groups" \
    3 "Create new group" \
    4 "Change GPU group" \
    5 "Restore GPU group" \
    6 "View GPU group"\
    7 "Exit" \
    2>"$TMPFILE"

  main_choice=$(<"$TMPFILE")
  rm -f "$TMPFILE"

  case "$main_choice" in
    1)
      dialog --clear --inputbox "Enter keyword to filter group names:" 10 60 2>"$SEARCHFILE"
      search_term=$(<"$SEARCHFILE")
      rm -f "$SEARCHFILE"
      ;;
    2)
      search_term=""
      ;;
    3)
      dialog --inputbox "Enter name for new group:" 10 50 2>"$TMPFILE"
      new_group=$(<"$TMPFILE")
      rm -f "$TMPFILE"
      if [ -n "$new_group" ]; then
        if sudo getent group "$new_group" >/dev/null; then
          dialog --msgbox "Group '$new_group' already exists." 8 40
        else
          if sudo groupadd "$new_group"; then
            dialog --msgbox "Group '$new_group' created successfully." 8 50
          else
            dialog --msgbox "Failed to create group. You may need sudo." 8 50
          fi
        fi
      fi
      continue
      ;;
    4)
      MENU_ITEMS=()
      while IFS=: read -r group_name _ gid users; do
        if [[ ${default_user_groups[$group_name]} ]]; then continue; fi
        if [[ $group_name =~ $system_group_pattern || $gid -lt 1000 ]]; then continue; fi
        if [[ -z "$search_term" || "$group_name" == *"$search_term"* ]]; then
            MENU_ITEMS+=("$group_name" "GID: $gid")
        fi
      done < /etc/group
      dialog --menu "Select a group to set as GPU device group:" 20 60 10 "${MENU_ITEMS[@]}" 2>"$TMPFILE"
      gpu_group=$(<"$TMPFILE")

      if [ -z "$gpu_group" ]; then
        dialog --msgbox "No group selected. Operation cancelled." 8 50
      else
        for dev in /dev/nvidia*; do
          [[ "$dev" != /dev/nvidia-caps* ]] && sudo chgrp "$gpu_group" "$dev" && sudo chmod 660 "$dev"
        done
        dialog --msgbox "GPU devices assigned to group '$gpu_group' with mode 660." 8 60
      fi
      continue
      ;;
    5)
      if sudo /sbin/ub-device-create; then
        dialog --msgbox "GPU device permissions restored via ub-device-create." 8 60
      else
        dialog --msgbox "Failed to restore GPU device permissions." 8 60
      fi
      continue
      ;;
    6)
      TMP_PERM=$(mktemp)
      ls -l /dev/nvidia* 2>/dev/null > "$TMP_PERM"
      if [ -s "$TMP_PERM" ]; then
        dialog --textbox "$TMP_PERM" 20 80
      else
        dialog --msgbox "No NVIDIA devices found." 8 40
      fi
      rm -f "$TMP_PERM"
      continue
      ;;
    7)
      clear
      exit 0
      ;;
    *)
      continue
      ;;
  esac

  # Build group menu
  MENU_ITEMS=()
  while IFS=: read -r group_name _ gid users; do
      if [[ ${default_user_groups[$group_name]} ]]; then continue; fi
      if [[ $group_name =~ $system_group_pattern || $gid -lt 1000 ]]; then continue; fi
      if [[ -z "$search_term" || "$group_name" == *"$search_term"* ]]; then
          MENU_ITEMS+=("$group_name" "GID: $gid")
      fi
  done < /etc/group

  if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
      dialog --title "No Match" --msgbox "No groups matched your search and filters." 8 60
      continue
  fi

  # Select group
  dialog --clear \
    --backtitle "Group Viewer" \
    --title "Select a group" \
    --menu "Select a group to manage:" \
    20 70 15 \
    "${MENU_ITEMS[@]}" 2>"$TMPFILE"

  response=$?
  selected_group=$(<"$TMPFILE")
  rm -f "$TMPFILE"

  if [ $response -ne 0 ]; then
      continue
  fi

  # === Group Management Loop ===
  while true; do
    dialog --clear \
      --backtitle "Group Viewer" \
      --title "Manage Group: $selected_group" \
      --menu "Choose an action for group '$selected_group':" \
      15 60 6 \
      1 "List group members" \
      2 "Add user to group" \
      3 "Remove user from group" \
      4 "Back to group list" \
      2>"$TMPFILE"

    choice=$(<"$TMPFILE")
    rm -f "$TMPFILE"

    case "$choice" in
      1)
        group_info=$(getent group "$selected_group")
        IFS=',' read -ra members <<< "$(echo "$group_info" | cut -d: -f4)"
        TABLE_FILE=$(mktemp)

        {
          if [ -z "${members[*]}" ]; then
            echo "(No users in this group)"
          else
            printf "%-20s %-6s %s\n" "Username" "UID" "Groups"
            printf "%-20s %-6s %s\n" "--------" "----" "------"

            for user in "${members[@]}"; do
              if id "$user" &>/dev/null; then
                uid=$(id -u "$user")
                groups=$(id -nG "$user" | tr ' ' ', ' | fold -s -w 50)
                first_line=$(echo "$groups" | head -n1)
                printf "%-20s %-6s %s\n" "$user" "$uid" "$first_line"
                echo "$groups" | tail -n +2 | while IFS= read -r line; do
                  printf "%-20s %-6s %s\n" " " " " "$line"
                done
              else
                printf "%-20s %-6s %s\n" "$user" "(N/A)" "(not found)"
              fi
            done
          fi
        } > "$TABLE_FILE"

        dialog --backtitle "Group Viewer" \
          --title "Group Members" \
          --textbox "$TABLE_FILE" 20 80
        rm -f "$TABLE_FILE"
        ;;

      2)
        MENU_ITEMS=()
        for dir in /home/*; do
          user=$(basename "$dir")
          if id "$user" &>/dev/null; then
            MENU_ITEMS+=("$user" "")
          fi
        done

        if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
          dialog --msgbox "No eligible users found in /home." 8 40
          continue
        fi

        dialog --menu "Select user to add to '$selected_group':" 20 50 10 "${MENU_ITEMS[@]}" 2>"$TMPFILE"
        new_user=$(<"$TMPFILE")
        rm -f "$TMPFILE"

        if [ -n "$new_user" ]; then
          sudo usermod -aG "$selected_group" "$new_user"
          if [ $? -eq 0 ]; then
            dialog --msgbox "User '$new_user' added to group '$selected_group'.\n\nNote: The user must log out and log back in for the group change to take effect." 10 60
          else
            dialog --msgbox "Failed to add user. You may need sudo permission." 8 60
          fi
        fi
        ;;

      3)
        group_info=$(getent group "$selected_group")
        IFS=',' read -ra members <<< "$(echo "$group_info" | cut -d: -f4)"

        if [ ${#members[@]} -eq 0 ]; then
          dialog --msgbox "No users in group '$selected_group' to remove." 8 50
          continue
        fi

        MENU_ITEMS=()
        for user in "${members[@]}"; do
          MENU_ITEMS+=("$user" "")
        done

        dialog --menu "Select a user to remove from '$selected_group':" \
          20 50 10 "${MENU_ITEMS[@]}" 2>"$TMPFILE"
        selected_user=$(<"$TMPFILE")
        rm -f "$TMPFILE"

        if [ -n "$selected_user" ]; then
          current_groups=$(id -nG "$selected_user" | tr ' ' '\n' | grep -v "^$selected_group$")
          new_group_list=$(echo "$current_groups" | paste -sd,)

          sudo usermod -G "$new_group_list" "$selected_user"
          if [ $? -eq 0 ]; then
            dialog --msgbox "User '$selected_user' removed from group '$selected_group'.\n\nNote: The user must log out and log back in for the group change to take effect." 10 60
          else
            dialog --msgbox "Failed to remove user. You may need sudo." 8 60
          fi
        fi
        ;;

      4)
        break
        ;;
    esac
  done
done
