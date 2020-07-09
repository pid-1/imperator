#!/bin/bash
# fromconf.sh

PROGDIR=$( cd $(dirname "${BASH_SOURCE[0]}") && pwd )
CONFFILE="${PROGDIR}/config.ini"


# Sigh... yes, there are certainly ways to get around this. But why. The only
# person who should be editing the config file is you. Don't use substitution.
sanitize_input ()
{
   echo -e "$( echo -e "$1" | sed -E 's/[\$\`]//g' )"
   # Need to use a pipe here, rather than the herestring, as it was improperly
   # stripping the '\' from escape sequences.
}


handle_var ()
{
   # Assigns value to specified variable
   local _VAR="$1"
   local _LINE="$2"

   eval "${_VAR}=${_LINE}"
}


handle_iarr ()
{
   # For handling indexed arrays
   local _VAR="$1"
   local _LINE="$2"

   eval "${_VAR}+=(${_LINE})"
}


handle_aarr ()
{
   # For handling associative arrays
   local _VAR="$1"
   local _LINE="$2"
   local _key _value

   IFS='=' read -r _key _value <<< "$_LINE"
   eval "$_VAR[${_key}]=${_value}"
}


fromconf ()
{
   local _VAR="$1"
   local _TYPE="$2"
   local _FOUND

   [[ -z "${_VAR}" ]] \
      && echo "\"_VAR\" not passed in." \
      && exit 1

   [[ -z "${_TYPE}" ]] && echo "\"_TYPE\" not passed in." \
      && exit 1

   while read -r line ; do
      CHAR1=$( sed -E 's/(.).*/\1/g' <<< "$line" )
      [[ "$CHAR1" == '#' ]] && continue

      HEADING=$(sed -E 's/^\[(.*)\]$/\1/g' <<< "$line")
      [[ "$HEADING" == "$_VAR" ]] && _FOUND=True && continue

      if [[ "$line" == "" ]] ; then
         [[ "$_FOUND" == True ]] && break || continue
      fi

      if [[ "$_FOUND" == True ]] ; then
         line="$( sanitize_input $line )"
         case $_TYPE in
            var) handle_var "$_VAR" "$line" ;;
            iarr) handle_iarr "$_VAR" "$line" ;;
            aarr) handle_aarr "$_VAR" "$line" ;;
         esac
      fi
   done < $CONFFILE
}
