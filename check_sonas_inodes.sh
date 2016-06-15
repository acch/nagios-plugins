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

# Name:               Check IBM Storwize V7000 Unified / SONAS Inodes
# Author:             Achim Christ - achim(dot)christ(at)gmail(dot)com
# Version:            1.0
# Dependencies:       openssh - OpenSSH SSH client (remote login program)
#                     bc - An arbitrary precision calculator language
# Website:            https://github.com/acch/nagios-plugins

# This bash script reports on the number of inodes in an IBM Storwize V7000 Unified / SONAS system.
# The number of used and maximum inodes for the given fileset in the given filesystem is reported, along with a utilization percentage.
# The plugin produces Nagios performance data so it can be graphed.

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
#     command_name         check_sonas_inodes
#     command_line         /path/to/check_sonas_inodes.sh -H $HOSTADDRESS$ -u $ARG1$ -F $ARG2$ -f $ARG3$
#   }
#   define service{
#     host_name            <your_system>
#     service_description  Fileset Inodes
#     check_command        check_sonas_inodes!nagios!filesystem!fileset
#   }

# Version History:
# 1.0    14.6.2016    Initial Release

#####################
### Configuration ###
#####################

# Warning threshold (inode utilization %)
warn_thresh=80  # This is the default which can be overridden with commandline parameters
# Critical threshold (inode utilization %))
crit_thresh=90  # This is the default which can be overridden with commandline parameters

# Modify the following filenames to match your environment

# Path to the SSH private key file used for authentication: (create a private/public key pair with the 'ssh-keygen' command)
identity_file="$HOME/.ssh/id_rsa"  # Be sure this is readable by Nagios user!

# Path to a temporary file holding the remote command output while it is being parsed by the script:
tmp_file="/tmp/check_sonas_inodes_$RANDOM.tmp"  # Be sure that this is writable by Nagios user!

####################################
### Do not edit below this line! ###
####################################

error_usage () {
  echo "Usage: $0 -H <host_address> -u <username> -F <filesystem> -f <fileset> [-w <warning_threshold>] [-c <critical_threshold>]"
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
if [ $# -ne 8 ]  && [ $# -ne 10 ] && [ $# -ne 12 ]; then error_usage; fi

# Check commandline options
while getopts 'H:u:F:f:w:c:' OPT; do
  case $OPT in
    H) hostaddress=$OPTARG ;;
    u) username=$OPTARG ;;
    F) filesystem=$OPTARG ;;
    f) fileset=$OPTARG ;;
    w) warn_thresh=$OPTARG ;;
    c) crit_thresh=$OPTARG ;;
    *) error_usage ;;
  esac
done

# Check for mandatory options
if [ -z "$hostaddress" ] || [ -z "$username" ] || [ -z "$filesystem" ] || [ -z "$fileset" ]; then error_usage; fi

# Check if thresholds are numbers
if ! [[ "$warn_thresh" =~ ^[[:digit:]]+$ ]] || ! [[ "$crit_thresh" =~ ^[[:digit:]]+$ ]]; then error_usage; fi

#################
# Sanity checks #
#################

# Check for dependencies
if [ ! -x /usr/bin/ssh ]
then
  echo "'openssh' not found - please install it!"
  exit 3
fi

if [ ! -x /usr/bin/bc ]
then
  echo "'bc' not found - please install it!"
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

# Initialize performance data and output
perfdata=""
output=""

# Initialize counter
fileset_found=0

##########################
# Check number of inodes #
##########################

# Execute remote command
$rsh "lsfset ${filesystem} -v -Y" &> $tmp_file
RC=$?

# Check SSH return code
if [ "$RC" -ne 0 ] && [ "$RC" -ne 9 ]; then error_login; fi

# Remove header from remote command output
sed '/HEADER/d' -i $tmp_file

# Check for errors
if grep -q 'EFSSP0010C' $tmp_file
then
  # EFSSP0010C - filesystem does not exist
  echo "Filesystem ${filesystem} not found!"
  rm $tmp_file
  exit 3
fi

# Parse remote command output
while read line
do
  # Check for specified fileset
  if [ "$(echo $line | cut -d : -f 8)" == "$fileset" ]
  then
    # Remember that fileset was found
    fileset_found=1

    # Retrieve used and max. inodes
    inodes_used=$(echo "$line" | cut -d : -f 17)
    inodes_max=$(echo "$line" | cut -d : -f 20)

    # Produce output
    utilization=$(echo "100*${inodes_used}/${inodes_max}" | bc)
    output="${utilization} % inodes used (${inodes_used} out of ${inodes_max})"

    # Produce performance data
    perfdata="inodes=${utilization}%;${warn_thresh};${crit_thresh};0;100"

    # Check if utilization is above threshold
    if [ $(echo "${utilization}>=${crit_thresh}" | bc) -eq 1 ] && [ "$return_code" -lt 2 ]
    then
      return_code=2
      return_status="CRITICAL"
    elif [ $(echo "${utilization}>=${warn_thresh}" | bc) -eq 1 ] && [ "$return_code" -lt 1 ]
    then
      return_code=1
      return_status="WARNING"
    fi
  fi
done < $tmp_file

# Check if fileset was found
if [ "$fileset_found" -eq 0 ]
then
  # Fileset does not exist
  echo "Fileset ${fileset} not found!"
  rm $tmp_file
  exit 3
fi

# Cleanup
rm $tmp_file

# Produce Nagios output
echo "INODES ${return_status} - ${output} |${perfdata}"
exit $return_code
