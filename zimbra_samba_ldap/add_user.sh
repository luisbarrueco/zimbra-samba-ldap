#!/bin/bash

# This script adds a Zimbra user account using zmprov commands.
# Copyright (C) 2012 Christian Lucas, Luis Barrueco

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

export TEXTDOMAINDIR=/opt/zimbra/scripts/file_server/locale
export TEXTDOMAIN=add_user.sh

prompt_values(){

	# DNS domain
	get_domain

	# Samba domain
	get_samba_domain

	# Distribution lists
	get_dls

	# Class of Service
	get_cos

	# Posix UID
	get_uid

	# Posix GID
	get_gid

	# username
	read -p "$(gettext -s "Username: ")" USERNAME
	[ "$USERNAME" = "" ] && gettext -s "ERROR: Invalid username" && exit 2

	# First name
	read -p "$(gettext -s "First name: ")" FIRST_NAME
	[ "$FIRST_NAME" = "" ] && gettext -s "ERROR: invalid first name" && exit 3

	# Last Name
	read -p "$(gettext -s "Last name: ")" SURNAME
	[ "$SURNAME" = "" ] && gettext -s "ERROR: invalid last name" && exit 4

	# Password
	read -s -p "$(gettext -s "Password: ")" PASSWORD
	[ "$PASSWORD" = "" ] && gettext -s "ERROR: invalid password" && exit 5


}

get_samba_domain(){

	local _SD_dn
	local _SD_ssid
	local _samba_domain_dn
	local _i
	local _resp
	local _limit
	local _msg

	echo ""
	gettext -s "Available samba domains: (please wait...)"
	local _samba_domains=$(ldapsearch -x -H ldapi:/// -D cn=config -w `zmlocalconfig -s zimbra_ldap_password | cut -d" " -f 3` "objectClass=sambaDomain" "dn" "sambaSID" | egrep "dn: |sambaSID: " | perl -pne 's|dn: (.*?)\n|$1:|' | perl -pne 's|sambaSID: ||')
	_i=1
	for _samba_domain in $_samba_domains; do
		_samba_domain_dn=$(echo $_samba_domain | cut -d":" -f 1)
		_SD_dn[$_i]=$_samba_domain_dn
		_SD_ssid[$_i]=$(echo $_samba_domain | cut -d":" -f 2)
		echo "$_i : $_samba_domain_dn"
		_i=$(($_i+1))
	done

	_resp=0
	_limit=$(($_i-1))
	_msg="Value (between 1 and %s): "
	_msg=$(gettext -s $_msg)
	until [ $_resp -le $(($_i-1)) ] && [ $_resp -ge 1 ]; do

		read -p "$(printf "$_msg" $_limit)" _resp
	done

	SAMBA_SID=${_SD_ssid[$_resp]}
	SMBDOMAIN=$(echo ${_SD_dn[$_resp]} | cut -d"," -f 1)
	echo $(gettext -s "Chosen SambaSID: ") $SAMBA_SID
}

get_domain(){
	local _msg=$(gettext -s "Domain")
	local _default_domain=$(zmprov gcf zimbraDefaultDomainName | cut -d" " -f 2)

	echo ""
	gettext -s "Available domains: (please wait...)"
	zmprov gad

	read -p "$_msg [$_default_domain]: " DOMAIN
	[ "$DOMAIN" = "" ] && DOMAIN=$_default_domain
}

used_uid(){
    # checks if uid (first argument) is already used
    # returns 1 if used, else 0
    local _uid="$1"
    local _check=$(ldapsearch -x -H ldapi:/// -D cn=config -w `zmlocalconfig -s zimbra_ldap_password | cut -d" " -f 3` "objectClass=posixAccount" "uidNumber" | egrep "uidNumber: " | cut -d" " -f 2 | egrep "^$_uid$")
    if [ "$_check" = "$_uid" ] ; then
        echo "1"
    else
        echo "0"
    fi
}

get_dls(){
	local _opt

	echo ""
	gettext -s "Available distribution lists: (please wait...)" 
	local _options=$(zmprov gadl)
	LISTS=""
	PS3=$(gettext -s "Choose an option. Press Ctrl-d when done > ")
	select _opt in $_options; do
		if [ -z "$_opt" ]; then
			gettext -s "Invalid selection"
		else
			LISTS="$LISTS $_opt"
		fi
		echo $(gettext -s "Current selection: ") $LISTS
	done
	echo ""
	echo $(gettext -s "The following lists have been selected: ") $LISTS
}

get_cos(){
	echo ""
	gettext -s "Available Classes of service: (please wait...)"
	local _all_coss=$(zmprov gac)
	echo $_all_coss | perl -pne "s|\s|\n|g"
	local _default_cos=$(echo $_all_coss | cut -d" " -f 1)
	local _msg=$(gettext -s "Class of service")
	read -p "$_msg [$_default_cos]: " COSNAME
	[ "$COSNAME" = "" ] && COSNAME=$_default_cos
	COSID=$(zmprov gc $COSNAME | grep 'zimbraId:' | cut -d' ' -f2)
	[ "$COSID" = "" ] && gettext -s "ERROR: Non-existent class of service" && exit 1
}

get_gid(){
	echo ""
	gettext -s "Available groups: (please wait...)"
	ldapsearch -x -H ldapi:/// -D cn=config -w `zmlocalconfig -s zimbra_ldap_password | cut -d" " -f 3` "objectClass=posixGroup" "dn" "gidNumber" | egrep "dn: |gidNumber: " | perl -pne 's|gidNumber: (.*?)$|$1|' | perl -pne 's|dn: (.*)\n$|$1 <--- |'
	echo ""
	read -p "$(gettext -s "Choose the group identifier: ")" GID
	ldapsearch -x -H ldapi:/// -D cn=config -w `zmlocalconfig -s zimbra_ldap_password | cut -d" " -f 3` "objectClass=posixGroup" "gidNumber" | egrep "^gidNumber: $GID$" >/dev/null || (gettext -s "ERROR: invalid group identifier" && exit 10)
	
}

get_uid(){
	local _uid=""
	_uid=$(ldapsearch -x -H ldapi:/// -D cn=config -w `zmlocalconfig -s zimbra_ldap_password | cut -d" " -f 3` "objectClass=posixAccount" "uidNumber" | egrep "uidNumber: " | cut -d" " -f 2 | sort | tail -1)
	if [ "$_uid" = "" ] ; then
		gettext -s "ERROR: Could not find a new user id"
		exit 11
	else
		while [ $(used_uid $_uid) = "1" ] ; do
			_uid=$(($_uid+1))
		done
	fi
	USER_UID=$_uid
}

add_user_za(){

	# NT is an unsalted md4 hash of the password
	local _nt_hash=$(printf '%s' "$PASSWORD" | iconv -t utf16le | openssl md4 | cut -d" " -f 2 | tr "a-z" "A-Z")

	gettext -s "Adding user..."
	zmprov ca ${USERNAME}@${DOMAIN} $PASSWORD \
		displayName "$FIRST_NAME $SURNAME" \
		zimbraCOSid "$COSID" \
		givenName "$FIRST_NAME" \
		sn "$SURNAME" \
		gidNumber "$GID" \
		homeDirectory "/home/$USERNAME" \
		loginShell "/bin/nologin" \
		sambaAcctFlags "[UX]" \
		sambaDomainName "$SMBDOMAIN" \
		sambaSID "${SAMBA_SID}-$((USER_UID*2+1000))" \
		uidNumber "$USER_UID" \
		sambaNTPassword "$_nt_hash"
	
	for list in $LISTS; do
		gettext -s "Adding user to a distribution list..."
		zmprov adlm "$list" "${USERNAME}@${DOMAIN}"
	done
}


# main #
########

prompt_values

add_user_za && gettext -s "Done!" && exit 0
gettext -s "ERROR" ; exit 100
