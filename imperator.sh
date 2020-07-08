#!/bin/bash
# imperator.sh
#
# NOTES:
# 1. Could probably swap the color escapes to `tput`, as in the trap. It's more
#    portable, and less error prone when going through `sed` and such.
# 2. Potentially use 'config.ini' to log all the vars for paths, rather than
#    hard coding them.
# 3. Switch the colors to the config file. Will need to change to an associative
#    array. Something like the following:
#     >>> declare -A C  # "C" for "Colors"
#     >>> fromconf C "aarr"
#     >>> echo "${C[green]} This is green! ${C[reset]}"
# 4. Fix the super dirty case statement in check_services()

exit_handler ()
{
   echo "$(tput sgr0)"
}
trap exit_handler EXIT
# Just so we don't get stuck with whacky colors if exited mid- color escape.
# Using `tput` for portability, instead of relying on the correct escapes.

PROGDIR=$( cd $(dirname "${BASH_SOURCE[@]}") && pwd )
source "${PROGDIR}/lib.sh" # <-- "imports" the `fromconf` function

PATH_ROOT="/var/log/imperator"
[[ ! -d "$PATH_ROOT" ]] && sudo bash -c "mkdir -p $PATH_ROOT"
PATH_CONFIG="${HOME}/.config/imperator"
[[ ! -d "$PATH_ROOT" ]] && mkdir -p "$PATH_CONFIG"

PATH_ORPHANED="${PATH_ROOT}/orphaned"
PATH_PACMAN_DB="${PATH_ROOT}/explicit"
PATH_YAY_DB="${PATH_ROOT}/foreign"
PATH_UPGRADE_DATE="${HOME}/.config/imperator/syu-time"

black='\e[30m'
red='\e[31m'
yellow='\e[33m'
green='\e[32m'
bold='\e[1m'
reset='\e[0m'


check_services ()
{
   echo -e "\nRunning services:"

   declare -a _services
   fromconf _services "iarr"

   len_services=${#_services[@]}

   # Find the max length
   local max_len=0
   for _part in "${_services[@]}" ; do
      _len_part=$( printf "$_part" | wc -m )
      [[ $_len_part -gt $max_len ]] && max_len=$_len_part
   done

   for idx in "${!_services[@]}" ; do
      service=${_services[$idx]}

      str_len_service=$( printf "$service" | wc -m )
      offset=$(( $max_len - $str_len_service + 2 ))

      [[ $idx -eq $((${len_services} - 1)) ]] && spacer='└─' || spacer='├─'

      _running="$(systemctl is-active ${service})"
      case "$_running" in
         #                      Service: Active
         #----------------------------------------------------------------------
         active)
            _running="${green}${_running}${reset}"
            printf "   $spacer $service %${offset}s${_running}\n"
            ;;

         #                     Service: Inactive
         #----------------------------------------------------------------------
         # EDIT
         # This is super dirty--should definitely handle this with its
         # own function, rather than part of a case statement. Just
         # dropping in here to get the functionality set, will then
         # wrap into a function later.
         inactive)
            _running="${yellow}${_running}${reset}"
            printf "   $spacer $service %${offset}s${_running}\n"

            [[ "$spacer" == '└─' ]] && bar=' ' || bar='│'
            printf "   ${bar}   ${black}└─ restart?${reset} ${bold}" ; read ans ; printf "${reset}"

            if [[ "$ans" =~ [Yy] ]] ; then
               sudo bash -c "systemctl restart $service &>/dev/null"
            else
               printf "\e[1A\e[19C${black}(skipped)${reset}\n"
            fi
            ;;
      esac
   done

   echo -e "\nFailed services:"
   failed_services=$( awk '{print $2}' <(systemctl --failed | grep ●) )
   if [[ -n "$failed_services" ]] ; then
      for _failed in "${failed_services[@]}" ; do
         printf "   ◦ ${red}${_failed}${reset}"
      done
   else
      echo -e "   └─ ${green}0${reset} failed"
   fi
}


check_packages ()
{
   echo -e "\nPackages:"

   # Similar in implementation as the max_len function.
   # Can check the offset for numbers in this format:
   #  (7) packages
   #  (100) something
   # With the following:
   #  $(( $( echo 'l(1400) / l(10)' | bc -l | sed 's/\..*//g' ) + 1 ))
   # Need to add the +1 to offset the 0-index:
   #  1400: 1(10^3), 4(10^2), 0(10^1), 0(10^0)
   #           3        2        1        0
   # Then need an additional offset of +3 for the ["(", ")", " "] for spacing.

   #                     Explicitly Installed Packages
   #----------------------------------------------------------------------------
   sudo bash -c "comm -23 <(pacman -Qqe | sort) <(pacman -Qqg base-devel) > $PATH_PACMAN_DB"
   _explicit_path=" ${black}── ${PATH_PACMAN_DB}${reset}"
   _explicitly_installed=$( cat $PATH_PACMAN_DB | wc -l )
   printf "   (${_explicitly_installed}) explicitly installed${_explicit_path}\n"

   #                       Foreign Installed Packages
   #----------------------------------------------------------------------------
   sudo bash -c "pacman -Qqm > $PATH_YAY_DB"
   _foreign_path=" ${black}── ${PATH_YAY_DB}${reset}"
   _foreign_installed=$( cat $PATH_YAY_DB | wc -l )
   printf "   (${_foreign_installed}) foreign installed (yay/yaourt)${_foreign_path}\n"

   #                            Package Orphans
   #----------------------------------------------------------------------------
   sudo bash -c "pacman -Qqdt > ${PATH_ORPHANED}"
   _orphaned_path=" ${black}── ${PATH_ORPHANED}${reset}"
   _num_orphaned=$( cat "$PATH_ORPHANED" | wc -l )
   if [[ ${_num_orphaned} -eq 0 ]] ; then
      printf "   (${green}${_num_orphaned}${reset}) orphaned\n"
   else
      printf "   ${yellow}(${_num_orphaned})${reset} orphaned${_orphaned_path}\n"
      printf "    ${black}└─ remove?${reset} ${bold}" ; read ans ; printf "${reset}"
      if [[ "$ans" =~ [Yy] ]] ; then
         sudo bash -c "pacman -Rns --noconfirm - < ${PATH_ORPHANED} >${PATH_ROOT}/pacman-Rns${reset}"
         printf "       ${black}└─ log: ${PATH_ROOT}/pacman-Rns${reset}\n"
      else
         printf "\e[1A\e[15C${black}(skipped)${reset}\n"
      fi
   fi

   #                         Time Since Last -Syu
   #----------------------------------------------------------------------------
   # Time coming from pacman hook in: /etc/pacman.d/hooks/syu-time.hook
   if [[ -f "$PATH_UPGRADE_DATE" ]] ; then
      echo -e "\nTime since last -Syu:"

      prev_date=$(cat "$PATH_UPGRADE_DATE")
      date_diff=$(printf '%.1f\n' $(bc -l <<< "($(date +%s) - ${prev_date}) / (3600*24)" ))

      date_color=${red}
      [[ $(awk '$1 < 7 {print "True"}' <<< "$date_diff") ]] && date_color=$yellow
      [[ $(awk '$1 < 3 {print "True"}' <<< "$date_diff") ]] && date_color=$green
      printf "   └─ ${date_color}${date_diff}${reset} day(s)\n"
   fi
}


backup_config_files ()
{
   printf "\nBacking up config files:\n"

   declare -A backup_files
   fromconf backup_files "aarr"

   # Find the max length
   local max_len=0
   for _part in "${!backup_files[@]}" ; do
      _len_part=$( printf "$_part" | wc -m )
      [[ $_len_part -gt $max_len ]] && max_len=$_len_part
   done

   for idx in "${!backup_files[@]}" ; do
      str_len_config=$( printf "$idx" | wc -m )
      offset=$(( $max_len - $str_len_config + 2))

      printf "   ◦ ${idx}"

      local PATH_DOTFILES
      fromconf PATH_DOTFILES "var"

      #                         `scp` dotfiles
      #-------------------------------------------------------------------------
      scp_err=$( scp "${backup_files[$idx]}" ${PATH_DOTFILES}${idx} 2>&1)
      if [[ $? -eq 0 ]] ; then
         printf "%${offset}s${black}──${reset}  ${green}done${reset}\n"
      else
         printf "%${offset}s${black}──${reset}  ${red}failed${reset}\n"
         printf "      └─ ${black}$scp_err${reset}\n"
      fi
   done
}


prune_paccache ()
{
   printf "\nPaccache:\n"

   #                            Clean Old Cache
   #----------------------------------------------------------------------------
   printf "   ├─ Clean cached >3 versions? ${black}(y/n)${reset} ${bold}"
   read ans ; printf "${reset}"
   if [[ "$ans" =~ [Yy] ]] ; then
      sudo bash -c "paccache -r >${PATH_ROOT}/paccache-r"
      printf "   │   ${black}└─ log: ${PATH_ROOT}/paccache-r${reset}\n"
   else
      printf "\e[1A\e[38C${black}(skipped)${reset}\n"
   fi

   #                          Clean Uninstalled
   #----------------------------------------------------------------------------
   printf "   └─ Clean uninstalled packages? ${black}(y/n)${reset} ${bold}"
   read ans ; printf "${reset}"
   if [[ "$ans" =~ [Yy] ]] ; then
      sudo bash -c "paccache -ruk0 >${PATH_ROOT}/paccache-ruk0"
      printf "       ${black}└─ log: ${PATH_ROOT}/paccache-ruk0${reset}\n"
   else
      printf "\e[1A\e[40C${black}(skipped)${reset}\n"
   fi
}


list_pac_files ()
{
   printf "\nHandle .pac* files ${black}── ${PATH_ROOT}/pacfiles${reset}\n"

   #                       List .pac(save|new) Files
   #----------------------------------------------------------------------------
   sudo bash -c "find /etc/ -regextype posix-extended -regex '.*\.pac(save|new)$' > ${PATH_ROOT}/pacfiles"
   mapfile -t _pacfiles < "${PATH_ROOT}/pacfiles"

   len_pacfiles="${#_pacfiles[@]}"
   if [[ $len_pacfiles -eq 0 ]] ; then
      printf "   └─ (${green}0${reset}) found, nice!\n"
   else
      for idx in "${!_pacfiles[@]}" ; do
         pac="${_pacfiles[$idx]}"
         pac=$( sed -E "s#(.*\/)(.*\.pac(save|new)$)#\\${black}\1\\${reset}\2#g" <<< "$pac" )

         [[ $idx -eq $((${len_pacfiles} - 1)) ]] && spacer='└─' || spacer='├─'

         printf "   ${spacer} ${pac}\n"
      done
   fi
}


main ()
{
   declare -a COMMANDS=( check_services
                         check_packages
                         backup_config_files
                         prune_paccache
                         list_pac_files )

   for cmd in "${COMMANDS[@]}" ; do
      $cmd
   done
}

main
