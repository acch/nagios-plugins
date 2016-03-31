#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2016 Achim Christ                                              #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to deal#
# in the Software without restriction, including without limitation the rights #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell    #
# copies of the Software, and to permit persons to whom the Software is        #
# furnished to do so, subject to the following conditions:                     #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,#
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE#
# SOFTWARE.                                                                    #
################################################################################

# Name:               Check IBM Storwize V7000 Unified / SONAS Replication
# Author:             Achim Christ - achim(dot)christ(at)gmail(dot)com
# Version:            1.0
# Dependencies:       openssh - OpenSSH SSH client (remote login program)
# Website:            https://github.com/acch/nagios-plugins

# This bash script checks the status of the last replication task of an IBM Storwize V7000 Unified / SONAS system.
# If the last replication for the given filesystem was unsuccessful, then the time at which the last successful replication completed is reported as well.

# The actual code is managed in the following GitHub rebository - please use the Issue Tracker to ask questions, report problems or request enhancements.
#   https://github.com/acch/nagios-plugins

# Disclaimer: This sample is provided 'as is', without any warranty or support. It is provided solely for demonstrative purposes - the end user must test and modify this sample to suit his or her particular environment. This code is provided for your convenience, only - though being tested, there's no guarantee that it doesn't seriously break things in your environment! If you decide to run it, you do so on your own risk!

# The script requires SSH Public Key Authentication for connecting to the Storwize V7000 Unified / SONAS system. SSH Public Key Authentication needs to be set up first, before running the script. To test your SSH configuration, try to login to Storwize V7000 Unified / SONAS via SSH from the Nagios server as the Nagios user - if this works without prompting you for a password you seem to have properly configured Public Key Authentication. If you get a "Permission denied" error when running the script, the most likely reason for that is Public Key Authentication not being configured correctly for the Nagios user (by default called 'nagios').

# It is strongly recommended to create a dedicated read-only Storwize V7000 Unified / SONAS user to be used by this script. This eases problem determination, allows for proper audit tracing and helps avoiding undesired side-effects. Also, it eliminates the risk of script errors having an impact on your actual production environment...

# To create a read-only user 'nagios' with password 'secret' on Storwize V7000 Unified / SONAS, run the following commands as the Nagios operating-system user (by default called 'nagios', too):
#   ssh admin@<mgmt_ip_address> mkuser nagios -p secret -g Monitor
#   ssh admin@<mgmt_ip_address> chuser nagios -k \"`cat ~/.ssh/id_rsa.pub`\"
# Note that you may need to modify the last command to point to the actual location of your SSH public key file used for authentication

# You may want to define the following Nagios constructs to use this script:
#   define command{
#     command_name         check_sonas_repl
#     command_line         /path/to/check_sonas_repl.sh -H $HOSTADDRESS$ -u $ARG1$ -F $ARG2$
#   }
#   define service{
#     host_name            <your_system>
#     service_description  Replication Status
#     check_command        check_sonas_repl!nagios!filesystem
#   }

# Version History:
# 1.0    31.3.2016    Initial Release

#####################
### Configuration ###
#####################

# Modify the following filenames to match your environment

# Path to the SSH private key file used for authentication: (create a private/public key pair with the 'ssh-keygen' command)
identity_file="$HOME/.ssh/id_rsa"  # Be sure this is readable by Nagios user!

# Path to a temporary file holding the remote command output while it is being parsed by the script:
tmp_file="/tmp/check_sonas_repl_$RANDOM.tmp"  # Be sure that this is writable by Nagios user!

####################################
### Do not edit below this line! ###
####################################

error_usage () {
  echo "Usage: $0 -H <host_address> -u <username> -F <filesystem>"
  exit 3
}

error_login () {
  echo "Error executing remote command - [$rsh] `cat $tmp_file`"
  rm $tmp_file
  exit 3
}

error_response () {
  echo "Error parsing remote command output: $*"
  rm $tmp_file
  exit 3
}

# Check number of commandline options
if [ $# -ne 6 ]; then error_usage; fi

# Check commandline options
while getopts 'H:u:F:' OPT; do
  case $OPT in
    H) hostaddress=$OPTARG ;;
    u) username=$OPTARG ;;
    F) filesystem=$OPTARG ;;
    *) error_usage ;;
  esac
done

# Check for mandatory options
if [ -z "$hostaddress" ] || [ -z "$username" ] || [ -z "$filesystem" ]; then error_usage; fi

#################
# Sanity checks #
#################

# Check for dependencies
if [ ! -x /usr/bin/ssh ]
then
  echo "'openssh' not found - please install it!"
  exit 3
fi

# Check if identity file is readable
if [ ! -r "$identity_file" ]
then
  echo "${identity_file} is not readable - please adjust its path!"
  exit 3
fi

# Check if temporary file is writable
if ! touch $tmp_file 2> /dev/null
then
  echo "${tmp_file} is not writable - please adjust its path!"
  exit 3
fi

# Compile SSH command using commandline options
rsh="/usr/bin/ssh \
  -o PasswordAuthentication=no \
  -o PubkeyAuthentication=yes \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 \
  -i $identity_file \
  $username@$hostaddress"

# Initialize return code
return_code=0
return_status="OK"

############################
# Check replication status #
############################

# Execute remote command
$rsh "lsrepl ${filesystem} -Y | grep -v HEADER" &> $tmp_file

# Check SSH return code
if [ $? -eq 255 ]; then error_login; fi

# Check for errors
if grep -q 'EFSSP0010C' $tmp_file
then
  # EFSSP0010C - filesystem does not exist
  echo "Filesystem ${filesystem} not found!"
  rm $tmp_file
  exit 3
fi

if [ $(cat $tmp_file | wc -l) -eq 0 ]
then
  # No replication for filesystem
  echo "No replication found for ${filesystem}!"
  rm $tmp_file
  exit 3
fi

# Check status of last run
last_status=$(tail -n 1 $tmp_file | cut -d : -f 9)

# Interpret last status
if [ "$last_status" == "FAILED" ] || [ "$last_status" == "STOPPED" ] || [ "$last_status" == "KILLED" ]
then

  # Last replication critical
  return_status="CRITICAL"
  return_code=2
  output="Last replication ${last_status}: $(tail -n 1 $tmp_file | cut -d : -f 10)"

  # Find last successful replication
  output="${output} - Last successful replication at '$(grep 'FINISHED' $tmp_file | tail -n 1 | cut -d ':' -f 11 | sed 's/\./:/g')'"

elif [ "$last_status" == "WARNING" ]
then

  # Last replication warning
  return_status="WARNING"
  return_code=1
  output="Last replication ${last_status} at '$(tail -n 1 $tmp_file | cut -d ':' -f 11)'"

else  # [ $last_status == "FINISHED" ]

  # Last replication successful
  output="Last replication ${last_status} at '$(tail -n 1 $tmp_file | cut -d ':' -f 11)'"

fi

# Cleanup
rm $tmp_file

# Produce Nagios output
echo "REPLICATION ${return_status} - ${output}"
exit $return_code
