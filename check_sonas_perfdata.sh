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

# Name:               Check IBM Storwize V7000 Unified / SONAS Performance
# Author:             Achim Christ - achim(dot)christ(at)gmail(dot)com
# Version:            1.0
# Dependencies:       openssh - OpenSSH SSH client (remote login program)
#                     bc - An arbitrary precision calculator language
# Website:            https://github.com/acch/nagios-plugins

# //This bash script checks health of an IBM Storwize V7000 Unified / SONAS system, using the 'lshealth' CLI command.
# //It allows for checking health of the system's front-end "FILE" component (both, Storwize V7000 Unified and SONAS), as well as health of the back-end "BLOCK" component (Storwize V7000 Unified, only - does not work with SONAS). The component to check is determined by the '-m' parameter: '-m f' checks health of the FILE component, '-m b' checks health of the BLOCK component.

# The following CLI command is used to retrieve performance data:
# lsperfdata
#   http://www-01.ibm.com/support/knowledgecenter/STAV45/com.ibm.sonas.doc/manpages/lsperfdata.html

# If the above command is unable to retrieve performance data, then one reason might be that performance data collection is not running, which can be verified and fixed with this CLI command:
# cfgperfcenter
#   http://www-01.ibm.com/support/knowledgecenter/STAV45/com.ibm.sonas.doc/manpages/cfgperfcenter.html

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
#     command_name    check_sonas_perfdata
#     command_line    /path/to/check_sonas_perfdata.sh -H $HOSTADDRESS$ -u $ARG1$ -m $ARG2$
#   }
#   define service{
#     host_name       <your_system>
#     service_description CPU Utilization
#     check_command   check_sonas_perfdata!nagios!c
#   }
#   define service{
#     host_name       <your_system>
#     service_description NETWORK Utilization
#     check_command   check_sonas_perfdata!nagios!n
#   }

# Version History:
# 1.0    15.02.2016    Initial Release

#####################
### Configuration ###
#####################

# Warning threshold (utilization percentage)
warn_thresh=80
# Critical threshold (utilization percentage)
crit_thresh=90

# Modify the following filenames to match your environment

# Path to the SSH private key file used for authentication: (create a private/public key pair with the 'ssh-keygen' command)
identity_file="$HOME/.ssh/id_rsa" # Be sure this is readable by Nagios user!

# Path to a temporary file holding the remote command output while it is being parsed by the script:
tmp_file="/tmp/check_sonas_perfdata_$RANDOM.tmp" # Be sure that this is writable by Nagios user!

####################################
### Do not edit below this line! ###
####################################

error_usage () {
  echo "Usage: $0 -H <host_address> -u <username> -m <metric>"
  echo "Supported metrics:"
  echo "  cpu_utilization [%]"
  echo "  cpu_iowait      [%]"
  echo "  public_network  [Bps]"
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
while getopts 'H:u:m:' OPT; do
  case $OPT in
    H) hostaddress=$OPTARG ;;
    u) username=$OPTARG ;;
    m) metric=$OPTARG ;;
    *) error_usage ;;
  esac
done

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
if [ ! -r $identity_file ]
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

#############################
# Retrieve performance data #
#############################
query=""
case "$metric" in
  "cpu_utilization")
    query="lsperfdata -g cpu_idle_usage -t minute -n all | grep -v 'EFSSG1000I' | tail -n 1"
    # Retrieves the statistics for the % of CPU spent idle on each of the nodes
  ;;
  "cpu_iowait")
    query="lsperfdata -g cpu_iowait_usage -t minute -n all | grep -v 'EFSSG1000I' | tail -n 1"
    # Retrieves the statistics for the % CPU spent for waiting for IO to complete on each of the nodes
  ;;
  "public_network")
    query="lsperfdata -g public_network_bytes_received -t minute -n all | grep -v 'EFSSG1000I' | tail -n 1"
    # Retrieves the total number of bytes received on all the client network interface of the nodes
    #lsperfdata -g public_network_bytes_sent -t minute -n all
    # Retrieves the total number of bytes sent on all the client network interface of the nodes
  ;;
  # Check not implemented
  *) error_usage ;;
esac

# Execute remote command
$rsh $query &> $tmp_file

# Check remote command return code
if [ $? -ne 0 ]; then error_login; fi

# Check for performance center errors
if grep 'EFSSG0002I' $tmp_file &> /dev/null
then
  echo "Error collecting performance data - check if performance center service is running using 'cfgperfcenter'"
  rm $tmp_file
  exit 3
fi

# Extract performance data from output
perfdata_raw=$(cat "$tmp_file" | cut -d ',' -f 3- | sed 's/,/ /g')

# Check extracted performance data
if [ "$perfdata_raw" == "" ]
then
  error_response $(cat "$tmp_file")
fi

# Initialize counter
num_nodes=0
perfdata=""

# Compute performance data output
for i in $perfdata_raw
do
  # Count number of nodes
  (( num_nodes += 1 ))

  case "$metric" in
    "cpu_utilization")
      # Calculate utilization from %idle
      utilization=$(echo "100-$i" | bc)
      # Concatenate performance data per node
      perfdata="$perfdata node${num_nodes}=${utilization}%;${warn_thresh};${crit_thresh};0;100"
    ;;
    "cpu_iowait")
      # Concatenate performance data per node
      perfdata="$perfdata node${num_nodes}=${i}%;${warn_thresh};${crit_thresh};0;100"
    ;;
    "public_network")
      # Concatenate performance data per node
      perfdata="$perfdata node${num_nodes}=${i}B;${warn_thresh};${crit_thresh};0;"
    ;;
  esac
done

# Cleanup
rm $tmp_file

# Produce Nagios output
echo "CPU OK |$perfdata"
exit $return_code
