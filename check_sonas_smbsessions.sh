#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2012 Achim Christ                                              #
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

# Name:               Check IBM Storwize V7000 Unified / SONAS SMB Sessions
# Author:             Achim Christ - achim(dot)christ(at)gmail(dot)com
# Version:            1.0
# Dependencies:       openssh - OpenSSH SSH client (remote login program)
#                     expect - programmed dialogue with interactive programs
# Website:            https://github.com/acch/nagios-plugins

# This bash script reports on the number of SMB sessions in an IBM Storwize V7000 Unified / SONAS system, by evaluating syslog entries in /var/log/messages.
# Storwize V7000 Unified / SONAS systems report the current number of sessions to each interface node's syslog. This script collects the current value and adds it up for all nodes.

# The actual code is managed in the following GitHub rebository - please use the Issue Tracker to ask questions, report problems or request enhancements.
#   https://github.com/acch/nagios-plugins

# Disclaimer: This sample is provided 'as is', without any warranty or support. It is provided solely for demonstrative purposes - the end user must test and modify this sample to suit his or her particular environment. This code is provided for your convenience, only - though being tested, there's no guarantee that it doesn't seriously break things in your environment! If you decide to run it, you do so on your own risk!

# It is strongly recommended to create a dedicated privileged Storwize V7000 Unified / SONAS user to be used by this script. This eases problem determination, allows for proper audit tracing and helps avoiding undesired side-effects.

# To create a privileged user 'nagios' with password 'secret' on Storwize V7000 Unified / SONAS, run the following command as the Nagios operating-system user (by default called 'nagios', too):
#   ssh admin@<mgmt_ip_address> mkuser nagios -p secret -g Privileged

# You may want to define the following Nagios constructs to use this script:
#   define command{
#     command_name    check_sonas_smbsessions
#     command_line    /path/to/check_sonas_smbsessions.sh -H $HOSTADDRESS$ -u $ARG1$
#   }
#   define service{
#     host_name       <your_system>
#     service_description SMB Sessions
#     check_command   check_sonas_health!nagios
#   }

# Version History:
# 1.0    10.2.2016    Initial Release

#####################
### Configuration ###
#####################

# Warning threshold (number of sessions per node)
warn_thresh=2000
# Critical threshold (number of sessions per node)
crit_thresh=4000

# Due to the Storwize V7000 Unified / SONAS security mechanisms we need to provide the password in clear text
# Ensure that the actual password is followed by "\n"
password="secret\n"

# Modify the following filenames to match your environment

# Path to a temporary file holding the remote command output while it is being parsed by the script:
tmp_file="/tmp/check_sonas_smbsessions_$RANDOM.tmp" # Be sure this is writable by Nagios user!

####################################
### Do not edit below this line! ###
####################################

error_usage () {
  echo "Usage: $0 -H <host_address> -u <username>"
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
if [ $# -ne 4 ]; then error_usage; fi

# Check commandline options
while getopts 'H:u:' OPT; do
  case $OPT in
    H) hostaddress=$OPTARG ;;
    u) username=$OPTARG ;;
    *) error_usage ;;
  esac
done

# Check for dependencies
if [ ! -x /usr/bin/ssh ]
then
  echo "'openssh' not found - please install it!"
  exit 3
fi

if [ ! -x /usr/bin/expect ]
then
  echo "'expect' not found - please install it!"
  exit 3
fi

# Compile SSH command using commandline options
rsh="/usr/bin/ssh \
  -t \
  -o PasswordAuthentication=yes \
  -o PubkeyAuthentication=no \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 \
  $username@$hostaddress"

# Initialize return code
return_code=0

################################
# Check number of SMB sessions #
################################

# Execute remote command
cmd="grep children /var/log/messages | tail -n 1"
/usr/bin/expect -c " \
  spawn ${rsh} sc onnode all \'${cmd}\'; \
  expect \"password\"; send ${password}; \
  expect \"Password\"; send ${password}; \
  interact" &> $tmp_file

# Check remote command return code
if [ $? -ne 0 ]; then error_login; fi

# Initialize counter
sum_sessions=0
num_nodes=0

# Sum up and count results
for i in $(grep --no-group-separator -A 1 "NODE" $tmp_file | grep -v "NODE" | awk '{print $4}')
do
  ((sum_sessions += i))
  ((num_nodes += 1))
done

# Calculate absolute thresholds (total number of sessions)
warn_shresh_abs=$((warn_thresh * num_nodes))
crit_shresh_abs=$((crit_thresh * num_nodes))

# Cleanup
rm $tmp_file

# Produce Nagios output
echo "SESSIONS OK - ${sum_sessions} sessions currently | sessions=${sum_sessions};${warn_shresh_abs};${crit_shresh_abs};0;${crit_shresh_abs}"
exit $retcode