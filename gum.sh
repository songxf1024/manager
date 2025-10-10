#!/bin/bash

# =====================================================
# GPU Group Manager - with "Add GPU to Group" Feature
# =====================================================

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
    --menu "Choose an action:" 17 60 8 \
    1 "Search Group" \
    2 "Browse Groups" \
    3 "Create Group" \
    4 "Change GPUs' Group" \
    5 "Restore GPUs' Group" \
    6 "View GPUs' Group" \
    7 "Add GPUs to Group" \
    8 "GPU Persistence Mode" \
    9 "Exit" \
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

        if systemctl is-active --quiet nvidia-persistenced; then
          dialog --yesno "'nvidia-persistenced' service is active.
        It may override your custom GPU group settings.

        Do you want to stop it temporarily?" 10 70
          if [ $? -eq 0 ]; then
            sudo systemctl stop nvidia-persistenced
            sudo systemctl disable nvidia-persistenced
          fi
        fi
      fi
      continue
      ;;
    5)
      if sudo /sbin/ub-device-create; then
        dialog --msgbox "GPU device permissions restored via ub-device-create." 8 60
        dialog --yesno "Do you want to re-enable NVIDIA persistence daemon to restore default management?" 10 70
        if [ $? -eq 0 ]; then
          sudo systemctl enable nvidia-persistenced
          sudo systemctl start nvidia-persistenced
          dialog --msgbox "'nvidia-persistenced' re-enabled." 8 50
        fi
        dialog --msgbox "Persistence Mode may have been disabled. You can use menu option 8 to re-enable it if needed." 8 60
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
      # --- Add GPU to Group ---
      MENU_ITEMS=()
      while IFS=: read -r group_name _ gid users; do
        if [[ ${default_user_groups[$group_name]} ]]; then continue; fi
        if [[ $group_name =~ $system_group_pattern || $gid -lt 1000 ]]; then continue; fi
        MENU_ITEMS+=("$group_name" "GID: $gid")
      done < /etc/group

      dialog --menu "Select a group to add GPU devices to:" 20 60 10 "${MENU_ITEMS[@]}" 2>"$TMPFILE"
      selected_group=$(<"$TMPFILE")
      rm -f "$TMPFILE"

      if [ -z "$selected_group" ]; then
        dialog --msgbox "No group selected. Operation cancelled." 8 50
        continue
      fi

      # --- Build complete GPU device list (excluding caps) ---
      GPU_LIST=()
      for dev in /dev/nvidia*; do
        [[ "$dev" == *"nvidia-caps"* ]] && continue
        [[ ! -e "$dev" ]] && continue
        GPU_LIST+=("$dev" "$dev" "off")   # tag, description, default off
      done

      if [ ${#GPU_LIST[@]} -eq 0 ]; then
        dialog --msgbox "No NVIDIA devices found on this system." 8 50
        continue
      fi

      dialog --checklist "Select GPU devices to add to group '$selected_group':" 22 75 15 "${GPU_LIST[@]}" 2>"$TMPFILE"
      selected_gpus=$(<"$TMPFILE")
      rm -f "$TMPFILE"

      if [ -z "$selected_gpus" ]; then
        dialog --msgbox "No GPU devices selected. Operation cancelled." 8 50
        continue
      fi

      # --- Confirm before applying ---
      confirm_text="The following devices will be added to group '$selected_group':\n\n"
      for gpu in $selected_gpus; do
        confirm_text+="  ${gpu//\"/}\n"
      done
      dialog --yesno "$confirm_text\n\nProceed?" 20 70
      response=$?
      if [ $response -ne 0 ]; then
        dialog --msgbox "Operation cancelled." 8 50
        continue
      fi

      # --- Apply changes ---
      for gpu in $selected_gpus; do
        gpu=${gpu//\"/}
        sudo chgrp "$selected_group" "$gpu" && sudo chmod 660 "$gpu"
      done

      dialog --msgbox "Selected GPU devices have been assigned to group '$selected_group' with mode 660. \n\n If 'nvidia-smi' does not show expected GPUs, run:\n\n  newgrp $selected_group" 10 70
      
      if systemctl is-active --quiet nvidia-persistenced; then
        dialog --yesno "'nvidia-persistenced' service is active.
      It may override your custom GPU group settings.

      Do you want to stop it temporarily?" 10 70
        if [ $? -eq 0 ]; then
          sudo systemctl stop nvidia-persistenced
        fi
      fi
      continue
      ;;
    8)
      TMP_STATUS=$(mktemp)
      nvidia-smi --query-gpu=persistence_mode --format=csv,noheader > "$TMP_STATUS" 2>/dev/null
      if [ $? -ne 0 ]; then
        dialog --msgbox "Failed to query GPU persistence mode.\nMake sure NVIDIA driver is loaded and nvidia-smi works." 10 70
        rm -f "$TMP_STATUS"
        continue
      fi

      total_gpus=$(wc -l < "$TMP_STATUS")
      enabled_gpus=$(grep -c "Enabled" "$TMP_STATUS")
      disabled_gpus=$(grep -c "Disabled" "$TMP_STATUS")

      if [ "$enabled_gpus" -eq "$total_gpus" ]; then
        # All GPU Enabled
        dialog --yesno "Persistence Mode is currently ENABLED for all $total_gpus GPUs.\n\nDo you want to DISABLE it?" 10 60
        if [ $? -eq 0 ]; then
          if sudo nvidia-smi -pm 0 >/dev/null 2>&1; then
            dialog --msgbox "Persistence Mode has been DISABLED for all GPUs." 8 60
          else
            dialog --msgbox "Failed to disable Persistence Mode. You may need sudo permission." 8 70
          fi
        fi
      elif [ "$disabled_gpus" -eq "$total_gpus" ]; then
        # All GPU Disabled
        dialog --yesno "Persistence Mode is currently DISABLED for all $total_gpus GPUs.\n\nDo you want to ENABLE it?" 10 60
        if [ $? -eq 0 ]; then
          if sudo nvidia-smi -pm 1 >/dev/null 2>&1; then
            dialog --msgbox "Persistence Mode has been ENABLED for all GPUs." 8 60
          else
            dialog --msgbox "Failed to enable Persistence Mode. You may need sudo permission." 8 70
          fi
        fi
      else
        # Mix
        dialog --yesno "Some GPUs have Persistence Mode ENABLED, some DISABLED.\n\nDo you want to ENABLE it for ALL GPUs?" 10 70
        if [ $? -eq 0 ]; then
          if sudo nvidia-smi -pm 1 >/dev/null 2>&1; then
            dialog --msgbox "Persistence Mode ENABLED for all GPUs." 8 60
          else
            dialog --msgbox "Failed to change Persistence Mode. You may need sudo permission." 8 70
          fi
        fi
      fi

      rm -f "$TMP_STATUS"
      continue
      ;;

    9)
      clear
      exit 0
      ;;
  esac

  # ========================
  # Group browsing section
  # ========================
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
            dialog --msgbox "User '$new_user' added to group '$selected_group'.\n\nNote: User must log out/in for change to take effect." 10 60
          else
            dialog --msgbox "Failed to add user. You may need sudo." 8 60
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
        dialog --menu "Select a user to remove from '$selected_group':" 20 50 10 "${MENU_ITEMS[@]}" 2>"$TMPFILE"
        selected_user=$(<"$TMPFILE")
        rm -f "$TMPFILE"
        if [ -n "$selected_user" ]; then
          current_groups=$(id -nG "$selected_user" | tr ' ' '\n' | grep -v "^$selected_group$")
          new_group_list=$(echo "$current_groups" | paste -sd,)
          sudo usermod -G "$new_group_list" "$selected_user"
          if [ $? -eq 0 ]; then
            dialog --msgbox "User '$selected_user' removed from group '$selected_group'.\n\nNote: Log out/in required." 10 60
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
