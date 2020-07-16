#!/bin/bash
# imperator.sh
#
# Currently all "backup_files" are being routed to the same place.
# Best way to handle is is probably in the "backup_files" dict. Instead of
# mapping "name" -> "location". Should map abs_src_loc -> rel_dest_loc:
#  >>> [ssh_base_dir]
#  ... senatus:/media/backup/populus/
#  ...
#  >>> [backup_files]
#  ... "/home/aurelius/.bashrc"="dotfiles/bashrc"
#  ... "/home/aurelius/.vimrc"="dotfiles/vimrc"
# The command then becomes (in short form):
#  >>> for src,dest in backup_files
#  ...    scp ${src} ${base_dir}${dest}
#
# The biggest problem with this utility currently is the 'fromconf' function.
# It is called to instantiate every variable. Thus, it must re-open, parse, and
# close the config file for every variable. Need to re-work how that function
# works.
# A better approach: read through the config file a single time. Use `eval` to
# directly create each variable, rather than needing to first define the var
# then search the config file and apply a value to it.
# The current approach is more apparent what variables are being used in this
# file, however speed is suffering.

exit_handler ()
{
   echo "$(tput sgr0)"
}
trap exit_handler EXIT
# Just so we don't get stuck with whacky colors if exited mid- color escape.
# Using `tput` for portability, instead of relying on the correct escapes.

#                               Set Up Paths
#-------------------------------------------------------------------------------
PROGDIR=$( cd $(dirname "${BASH_SOURCE[@]}") && pwd )
source "${PROGDIR}/lib.sh" # <-- "imports" the `fromconf` function

PATH_ROOT="/var/log/imperator"
[[ ! -d "$PATH_ROOT" ]] && sudo bash -c "mkdir -p $PATH_ROOT"
PATH_CONFIG="${HOME}/.config/imperator"
[[ ! -d "$PATH_CONFIG" ]] && mkdir -p "$PATH_CONFIG"

PATH_ORPHANED="${PATH_ROOT}/orphaned"
PATH_PACMAN_DB="${PATH_ROOT}/explicit"
PATH_YAY_DB="${PATH_ROOT}/foreign"
PATH_UPGRADE_DATE="${HOME}/.config/imperator/syu-time"

declare -A c
fromconf c "aarr"


check_services ()
{
   #                            System Services
   #----------------------------------------------------------------------------
   echo -e "\nRunning services:"

   declare -a services
   fromconf services "iarr"

   declare -a user_services
   fromconf user_services "iarr"

   num_services=${#services[@]}

   # First iteration...
   # To effectively space into columns. Iterate once through the list of
   # services to find the longest name length. Then can justify the right
   # column w/ the following:  offset = (longest - current) + whitespace
   declare -a all_services=("${services[@]}" "${user_services[@]}")
   local max_len=0
   for part in "${all_services[@]}" ; do
      len_part=$( printf "$part" | wc -m )
      [[ $len_part -gt $max_len ]] && max_len=$len_part
   done

   # Second iteration...
   # Prints services, displaying "active/inactive" status.
   for idx in "${!services[@]}" ; do
      serv=${services[$idx]}

      len_service=$( printf "$serv" | wc -m )
      offset=$(( $max_len - $len_service + 2 ))

      [[ $idx -eq $((${num_services} - 1)) ]] && tree='└─' || tree='├─'

      running="$(systemctl is-active ${serv})"
      case "$running" in
         active)
            printf "   $tree $serv %${offset}s${c[good]}${running}${c[rst]}\n"
            ;;
         inactive)
            printf "   $tree $serv %${offset}s${c[warn]}${running}${c[rst]}\n"

            [[ "$tree" == '└─' ]] && bar=' ' || bar='│'
            printf "   ${bar}   ${c[dim]}└─ restart?${c[rst]} ${c[bold]}" ; read ans ; printf "${c[rst]}"

            if [[ "$ans" =~ [Yy] ]] ; then
               sudo bash -c "systemctl restart $serv &>/dev/null"
            else
               printf "\e[1A\e[19C${c[dim]}(skipped)${c[rst]}\n"
            fi
            ;;
      esac  # case $running
   done  # for idx in user_services

   #                             User Services
   #----------------------------------------------------------------------------
   if [[ -n ${user_services} ]] ; then
      printf "${c[dim]}User services:${c[rst]}\n"

      num_u_services=${#user_services[@]}

      # Second iteration...
      # Prints services, displaying "active/inactive" status.
      for idx in "${!user_services[@]}" ; do
         serv=${user_services[$idx]}

         len_service=$( printf "$serv" | wc -m )
         offset=$(( $max_len - $len_service + 2 ))

         [[ $idx -eq $((${num_u_services} - 1)) ]] && tree='└─' || tree='├─'

         running="$(systemctl --user is-active ${serv})"
         case "$running" in
            active)
               printf "   $tree $serv %${offset}s${c[good]}${running}${c[rst]}\n"
               ;;
            inactive)
               printf "   $tree $serv %${offset}s${c[warn]}${running}${c[rst]}\n"

               [[ "$tree" == '└─' ]] && bar=' ' || bar='│'
               printf "   ${bar}   ${c[dim]}└─ restart?${c[rst]} ${c[bold]}" ; read ans ; printf "${c[rst]}"

               if [[ "$ans" =~ [Yy] ]] ; then
                  sudo bash -c "systemctl --user restart $serv &>/dev/null"
               else
                  printf "\e[1A\e[19C${c[dim]}(skipped)${c[rst]}\n"
               fi
               ;;
         esac  # case $running
      done  # for idx in user_services
   fi # if ${user_services}

   #                            Failed Services
   #----------------------------------------------------------------------------
   # Lists services listed as "failed" from $(systemctl --state=failed)
   # Does not prompt for any action--only informational
   echo -e "\nFailed services:"
   failed_services=$( awk '{print $2}' <(systemctl --failed | grep ●) )
   if [[ -n "$failed_services" ]] ; then
      for failed in "${failed_services[@]}" ; do
         printf "   ◦ ${c[crit]}${failed}${c[rst]}"
      done
   else
      echo -e "   └─ (${c[good]}0${c[rst]}) failed"
   fi

   #                          Failed User Services
   #----------------------------------------------------------------------------
   # Lists services listed as "failed" from $(systemctl --state=failed)
   # Does not prompt for any action--only informational
   printf "${c[dim]}User services:${c[rst]}\n"

   failed_u_services=$( awk '{print $2}' <(systemctl --user --failed | grep ●) )
   if [[ -n "$failed_u_services" ]] ; then
      for failed in "${failed_u_services[@]}" ; do
         printf "   ◦ ${c[crit]}${failed}${c[rst]}"
      done
   else
      echo -e "   └─ (${c[good]}0${c[rst]}) failed"
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
   explicit_path=" ${c[dim]}── ${PATH_PACMAN_DB}${c[rst]}"
   num_explicit=$( cat $PATH_PACMAN_DB | wc -l )
   printf "   (${num_explicit}) explicitly installed${explicit_path}\n"

   #                       Foreign Installed Packages
   #----------------------------------------------------------------------------
   sudo bash -c "pacman -Qqm > $PATH_YAY_DB"
   foreign_path=" ${c[dim]}── ${PATH_YAY_DB}${c[rst]}"
   num_foreign=$( cat $PATH_YAY_DB | wc -l )
   printf "   (${num_foreign}) foreign installed (yay/yaourt)${foreign_path}\n"

   #                            Package Orphans
   #----------------------------------------------------------------------------
   sudo bash -c "pacman -Qqdt > ${PATH_ORPHANED}"
   orphaned_path=" ${c[dim]}── ${PATH_ORPHANED}${c[rst]}"
   num_orphaned=$( cat "$PATH_ORPHANED" | wc -l )
   if [[ ${num_orphaned} -eq 0 ]] ; then
      printf "   (${c[good]}${num_orphaned}${c[rst]}) orphaned\n"
   else
      printf "   ${c[warn]}(${num_orphaned})${c[rst]} orphaned${orphaned_path}\n"
      printf "    ${c[dim]}└─ remove?${c[rst]} ${c[bold]}" ; read ans ; printf "${c[rst]}"
      if [[ "$ans" =~ [Yy] ]] ; then
         sudo bash -c "pacman -Rns --noconfirm - < ${PATH_ORPHANED} >${PATH_ROOT}/pacman-Rns${c[rst]}"
         printf "       ${c[dim]}└─ log: ${PATH_ROOT}/pacman-Rns${c[rst]}\n"
      else
         printf "\e[1A\e[15C${c[dim]}(skipped)${c[rst]}\n"
      fi
   fi

   #                         Time Since Last -Syu
   #----------------------------------------------------------------------------
   # Time coming from pacman hook in: /etc/pacman.d/hooks/syu-time.hook
   if [[ -f "$PATH_UPGRADE_DATE" ]] ; then
      echo -e "\nTime since last -Syu:"

      prev_date=$(cat "$PATH_UPGRADE_DATE")
      date_diff=$(printf '%.1f\n' $(bc -l <<< "($(date +%s) - ${prev_date}) / (3600*24)" ))

      date_color=${c[crit]}
      [[ $(awk '$1 < 7 {print "True"}' <<< "$date_diff") ]] && date_color=${c[warn]}
      [[ $(awk '$1 < 3 {print "True"}' <<< "$date_diff") ]] && date_color=${c[good]}
      printf "   └─ ${date_color}${date_diff}${c[rst]} day(s)\n"
   fi
}


backup_config_files ()
{
   printf "\nBacking up config files:\n"

   declare -A backup_files
   fromconf backup_files "aarr"

   # Find the max length
   local max_len=0
   for part in "${!backup_files[@]}" ; do
      len_part=$( printf "$part" | wc -m )
      [[ $len_part -gt $max_len ]] && max_len=$len_part
   done

   for idx in "${!backup_files[@]}" ; do
      str_len_config=$( printf "$idx" | wc -m )
      offset=$(( $max_len - $str_len_config + 2))

      printf "   ◦ ${idx}"

      local scp_dest
      fromconf scp_dest "var"

      #                         `scp` dotfiles
      #-------------------------------------------------------------------------
      # EDIT
      # May be better to write the output of the failed `scp`s to a logfile,
      # rather than printing to the screen. It's more "permanent" in case of the
      # screen clearing, needing to use the output in a followup script, etc.
      scp_err=$( scp "${backup_files[$idx]}" ${scp_dest}${idx} 2>&1)
      if [[ $? -eq 0 ]] ; then
         printf "%${offset}s${c[dim]}──${c[rst]}  ${c[good]}done${c[rst]}\n"
      else
         printf "%${offset}s${c[dim]}──${c[rst]}  ${c[crit]}failed${c[rst]}\n"
         printf "      └─ ${c[dim]}$scp_err${c[rst]}\n"
      fi
   done
}


prune_paccache ()
{
   printf "\nPaccache:\n"

   #                            Clean Old Cache
   #----------------------------------------------------------------------------
   printf "   ├─ Clean cached >3 versions? ${c[dim]}(y/n)${c[rst]} ${c[bold]}"
   read ans ; printf "${c[rst]}"
   if [[ "$ans" =~ [Yy] ]] ; then
      sudo bash -c "paccache -r >${PATH_ROOT}/paccache-r"
      printf "   │   ${c[dim]}└─ log: ${PATH_ROOT}/paccache-r${c[rst]}\n"
   else
      printf "\e[1A\e[38C${c[dim]}(skipped)${c[rst]}\n"
   fi

   #                          Clean Uninstalled
   #----------------------------------------------------------------------------
   printf "   └─ Clean uninstalled packages? ${c[dim]}(y/n)${c[rst]} ${c[bold]}"
   read ans ; printf "${c[rst]}"
   if [[ "$ans" =~ [Yy] ]] ; then
      sudo bash -c "paccache -ruk0 >${PATH_ROOT}/paccache-ruk0"
      printf "       ${c[dim]}└─ log: ${PATH_ROOT}/paccache-ruk0${c[rst]}\n"
   else
      printf "\e[1A\e[40C${c[dim]}(skipped)${c[rst]}\n"
   fi
}


list_pac_files ()
{
   printf "\nHandle .pac* files ${c[dim]}── ${PATH_ROOT}/pacfiles${c[rst]}\n"

   #                       List .pac(save|new) Files
   #----------------------------------------------------------------------------
   sudo bash -c "find /etc/ -regextype posix-extended -regex '.*\.pac(save|new)$' > ${PATH_ROOT}/pacfiles"
   readarray -t pacfiles < "${PATH_ROOT}/pacfiles"

   len_pacfiles="${#pacfiles[@]}"
   if [[ $len_pacfiles -eq 0 ]] ; then
      printf "   └─ (${c[good]}0${c[rst]}) found, nice!\n"
   else
      for idx in "${!pacfiles[@]}" ; do
         pac="${pacfiles[$idx]}"
         pac=$( sed -E "s#(.*\/)(.*\.pac(save|new)$)#\\${c[dim]}\1\\${c[rst]}\2#g" <<< "$pac" )

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
