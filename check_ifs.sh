#!/bin/bash

###############################################################################
# Copyright 2012 Achim Christ                                                 #
#                                                                             #
#   Licensed under the Apache License, Version 2.0 (the "License");           #
#   you may not use this file except in compliance with the License.          #
#   You may obtain a copy of the License at                                   #
#                                                                             #
#       http://www.apache.org/licenses/LICENSE-2.0                            #
#                                                                             #
#   Unless required by applicable law or agreed to in writing, software       #
#   distributed under the License is distributed on an "AS IS" BASIS,         #
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  #
#   See the License for the specific language governing permissions and       #
#   limitations under the License.                                            #
###############################################################################

# Name:		Check IBM Storwize V7000 Unified / SONAS
# Author:	Achim Christ - achim(dot)christ(at)gmail(dot)com
# Version:	1.0
# Dependencies:	openssh

# This bash script checks health of an IBM Storwize V7000 Unified / SONAS system, using the 'lshealth' CLI command.
# It allows checking health of the system's front-end "FILE" component (both, Storwize V7000 Unified and SONAS), as well as health of the back-end "BLOCK" component (Storwize V7000 Unified, only - does not work with SONAS). The component to check is determined by the '-m' parameter: '-m f' checks health of the FILE component, '-m b' checks health of the BLOCK component.

# Disclaimer: This sample is provided 'as is', without any warranty or support. It is provided solely for demonstrative purposes - the end user must test and modify this sample to suit his or her particular environment. This code is provided for your convenience, only - though being tested, there's no guarantee that it doesn't seriously break things in your environment! If you decide to run it, you do so on your own risk!

# The script requires SSH Public Key Authentication for connecting to the Storwize V7000 Unified / SONAS system. SSH Public Key Authentication needs to be set up first, before running the script. To test your SSH configuration, try to login to Storwize V7000 Unified / SONAS via SSH from the Nagios server as the Nagios user - if this works without prompting you for a password you seem to have properly configured Public Key Authentication. If you get a "Permission denied" error when running the script, the most likely reason for that is Public Key Authentication not being configured correctly for the Nagios user (by default called 'nagios').

# It is strongly recommended to create a dedicated read-only Storwize V7000 Unified / SONAS user to be used by this script. This eases problem determination, allows proper audit tracing and helps avoiding undesired side-effects. Also, it eliminates the risk of script errors having an impact to your actual production environment...

# To create a read-only user 'nagios' with password 'secret' on Storwize V7000 Unified / SONAS, run the following commands as the Nagios operating-system user (by default called 'nagios', too):
#   ssh admin@<mgmt_ip_address> mkuser nagios -p secret -g Monitor
#   ssh admin@<mgmt_ip_address> chuser nagios -k \"`cat ~/.ssh/id_rsa.pub`\"
# Note that you may need to modify the last command to point to the actual location of your SSH public key file used for authentication

# You may want to define the following Nagios constructs to use this script:
#   define command{
#     command_name    check_ifs
#     command_line    /path/to/check_ifs.sh -H $HOSTADDRESS$ -u $ARG1$ -m $ARG2$
#   }
#   define service{
#     use			generic-service
#     host_name			<your_system>
#     service_description	PING
#     check_command		check_ping!100.0,20%!500.0,60%
#   }
#   define service{
#     use			generic-service
#     host_name			<your_system>
#     service_description	BLOCK
#     check_command		check_ifs!nagios!b
#   }
#   define service{
#     use			generic-service
#     host_name			<your_system>
#     service_description	FILE
#     check_command		check_ifs!nagios!f
#   }


# Version History:
# 1.0		7.12.2012	Initial Release
#

#####################
### Configuration ###
#####################

# Modify the following filenames to match your environment

# Path to the SSH private key file used for authentication: (create a private/public key pair with the 'ssh-keygen' command)
identity_file="$HOME/.ssh/id_rsa" # Be sure this is readable by Nagios user!

# Path to a temporary file holding the remote command output while it is being parsed by the script:
tmp_file="/tmp/check_ifs_$RANDOM.tmp" # Be sure this is writable by Nagios user!

####################################
### Do not edit below this line! ###
####################################

error_usage () {
  echo "Usage: $0 -H <host_address> -u <username> -m [b|f]"
  exit 3
}

error_login () {
  echo "Error executing remote command - [$rsh] `cat $tmp_file`"
  rm $tmp_file
  exit 3
}

error_response () {
  echo "Error parsing remote command output: $1"
  rm $tmp_file
  exit 3
}

# Check number of commandline options
if [ $# -ne 6 ]; then error_usage; fi

# Check commandline options
while getopts 'H:u:m:' OPT; do
  case $OPT in
    H) hostaddress=$OPTARG ;;
    u) username=$OPTARG ;;
    m) mode=$OPTARG ;;
    *) error_usage ;;
  esac
done

# Compile SSH command using commandline options
rsh="/usr/bin/ssh \
  -o PasswordAuthentication=no \
  -o PubkeyAuthentication=yes \
  -o StrictHostKeyChecking=no \
  -i $identity_file \
  $username@$hostaddress"

# Initialize return code
return_code=0

case "$mode" in
  ##################################
  # Check health of FILE component #
  ##################################
  f)
    # Execute remote command
    $rsh "lshealth -Y | grep -v HEADER" &> $tmp_file

    # Check remote command return code
    if [ $? -ne 0 ]; then error_login; fi

    # Parse remote command output
    while read line
    do
      if [ $(echo "$line" | cut -d : -f 7) != "V7000" ] # Ignore V7000 sensors
      then
        case $(echo "$line" | cut -d : -f 9) in
          OK) # Sensor OK state -> do nothing
          ;;
          WARNING) # Sensor WARNING state
            if [ "$return_code" -lt 1 ]; then return_code=1; fi
            # Append sensor message to output
            if [ -n "$return_message" ]; then return_message="$return_message +++ "; fi
            return_message="${return_message}FILE WARNING - [`echo $line | cut -d : -f 7`:`echo $line | cut -d : -f 8`] `echo $line | cut -d : -f 10`"
          ;;
          ERROR) # Sensor ERROR state
            if [ "$return_code" -lt 2 ]; then return_code=2; fi
            # Append sensor message to output
            if [ -n "$return_message" ]; then return_message="$return_message +++ "; fi
            return_message="${return_message}FILE CRITICAL - [`echo $line | cut -d : -f 7`:`echo $line | cut -d : -f 8`] `echo $line | cut -d : -f 10`"
          ;;
          *) error_response $line ;;
        esac
      fi
    done < $tmp_file

    # No warnings/errors detected
    if [ "$return_code" -eq 0 ]; then return_message="FILE OK - All sensors OK"; fi

    # Cleanup
    rm $tmp_file
  ;;
  ###################################
  # Check health of BLOCK component #
  ###################################
  b)
    # Execute remote command
    $rsh "lshealth -i STRG -Y | grep -v HEADER" &> $tmp_file

    # Check remote command return code
    if [ $? -ne 0 ]; then error_login; fi

    # Parse remote command output
    while read line
    do
      case $(echo "$line" | cut -d : -f 10) in
        message) # Sensor OK state -> do nothing
        ;;
        warning) # Sensor WARNING state
          if [ "$return_code" -lt 1 ]; then return_code=1; fi
          # Append sensor message to output
          if [ -n "$return_message" ]; then return_message="$return_message +++ "; fi
          return_message="${return_message}BLOCK WARNING - [`echo $line | cut -d : -f 8`:`echo $line | cut -d : -f 9`] `echo $line | cut -d : -f 11`"
        ;;
        alert) # Sensor ERROR state
          if [ "$return_code" -lt 2 ]; then return_code=2; fi
          # Append sensor message to output
          if [ -n "$return_message" ]; then return_message="$return_message +++ "; fi
          return_message="${return_message}BLOCK CRITICAL - [`echo $line | cut -d : -f 8`:`echo $line | cut -d : -f 9`] `echo $line | cut -d : -f 11`"
        ;;
        *) error_response $line ;;
      esac
    done < $tmp_file

    # No warnings/errors detected
    if [ "$return_code" -eq 0 ]; then return_message="BLOCK OK - All sensors OK"; fi

    # Cleanup
    rm $tmp_file
  ;;
  # Check not implemented
  *) error_usage ;; 
esac

# Produce Nagios output
echo $return_message
exit $return_code

