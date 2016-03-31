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

# This bash script reports on various performance metrics of an IBM Storwize V7000 Unified / SONAS system, using the 'lsperfdata' CLI command.
# For a list of supported metrics run the script without any commandline arguments.
# The script uses the performance center service which needs to be running on all nodes of Storwize V7000 Unified / SONAS.
# The plugin produces Nagios performance data so it can be graphed.

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
#     command_name         check_sonas_perfdata
#     command_line         /path/to/check_sonas_perfdata.sh -H $HOSTADDRESS$ -u $ARG1$ -m $ARG2$ -w $ARG3$ -c $ARG4$
#   }
#   define service{
#     host_name            <your_system>
#     service_description  CPU Utilization
#     check_command        check_sonas_perfdata!nagios!cpu_utilization!80!90
#   }
#   define service{
#     host_name            <your_system>
#     service_description  CPU IO Wait
#     check_command        check_sonas_perfdata!nagios!cpu_iowait!3!5
#   }
#   define service{
#     host_name            <your_system>
#     service_description  NETWORK Throughput
#     check_command        check_sonas_perfdata!nagios!public_network!10000000!20000000
#   }
#   define service{
#     host_name            <your_system>
#     service_description  GPFS Throughput
#     check_command        check_sonas_perfdata!nagios!gpfs_throughput!10000000!20000000
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
tmp_file="/tmp/check_sonas_perfdata_$RANDOM.tmp"  # Be sure that this is writable by Nagios user!

####################################
### Do not edit below this line! ###
####################################

error_usage () {
  echo "Usage: $0 -H <host_address> -u <username> -m <metric> -w <warning_threshold> -c <critical_threshold>"
  echo "Supported metrics:  [unit]"
  echo "  cpu_utilization   [%]"
  echo "  cpu_iowait        [%]"
  echo "  public_network    [Bps]"
  echo "  gpfs_throughput   [Bps]"
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
if [ $# -ne 10 ]; then error_usage; fi

# Check commandline options
while getopts 'H:u:m:w:c:' OPT; do
  case $OPT in
    H) hostaddress=$OPTARG ;;
    u) username=$OPTARG ;;
    m) metric=$OPTARG ;;
    w) warn_thresh=$OPTARG ;;
    c) crit_thresh=$OPTARG ;;
    *) error_usage ;;
  esac
done

# Check for mandatory options
if [ ! -n "$hostaddress" ] || [ ! -n "$username" ] || [ ! -n "$metric" ] || [ ! -n "$warn_thresh" ] || [ ! -n "$crit_thresh" ]; then error_usage; fi

# Check if thresholds are numbers
if ! [[ $warn_thresh =~ ^[[:digit:]]+$ ]] || ! [[ $warn_thresh =~ ^[[:digit:]]+$ ]]; then error_usage; fi

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
count_metric_1=0
count_metric_2=0

# Prepare nodename array
declare -A nodenames

#######################
# Retrieve node names #
#######################

# Execute remote command
$rsh "lsnode -v -Y | grep -v HEADER" &> $tmp_file

# Check SSH return code
if [ $? -eq 255 ]; then error_login; fi

# Parse remote command output
while read line
do
  # Remember IP and associated nodename
  nodenames["$(echo $line | cut -d ':' -f 8)"]="$(echo $line | cut -d ':' -f 7)"
done < $tmp_file

#############################
# Retrieve performance data #
#############################

# Query multiple metrics if required
repeat=1
while [ "$repeat" -gt 0 ]
do
  query=""
  case "$metric" in
    "cpu_utilization")
      query="lsperfdata -g cpu_idle_usage -t hour -n all | grep -v 'EFSSG1000I'"
      # Retrieves the statistics for the % of CPU spent idle on each of the nodes
    ;;
    "cpu_iowait")
      query="lsperfdata -g cpu_iowait_usage -t hour -n all | grep -v 'EFSSG1000I'"
      # Retrieves the statistics for the % CPU spent for waiting for IO to complete on each of the nodes
    ;;
    "public_network")
      if [ "$perfdata" == "" ]
      then
        # Repeat twice
        repeat=2

        # First repeat
        query="lsperfdata -g public_network_bytes_received -t hour -n all | grep -v 'EFSSG1000I'"
        # Retrieves the total number of bytes received on all the client network interface of the nodes
      else
        # Second repeat
        query="lsperfdata -g public_network_bytes_sent -t hour -n all | grep -v 'EFSSG1000I'"
        # Retrieves the total number of bytes sent on all the client network interface of the nodes
      fi
    ;;
    "gpfs_throughput")
      query="lsperfdata -g cluster_throughput -t hour | grep -v 'EFSSG1000I'"
      # Retrieves the number of bytes read and written across all the filesystems on all the nodes of the GPFS cluster
    ;;

    # Also available:
    # client_throughput                Retrieves the total bytes received and total bytes sent across all the client network interface on all the interface nodes. Timeperiod is the only parameter for this graph.
    # cluster_create_delete_latency    Retrieves the latency of the file create and delete operations across all the filesystems on all the nodes of the GPFS cluster. Timeperiod is the only mandatory parameter for this graph.
    # cluster_create_delete_operations Retrieves the number of file create and delete operations across all the filesystems on all the nodes of the GPFS cluster. Timeperiod is the only mandatory parameter for this graph.
    # cluster_open_close_latency       Retrieves the latency of file open and close operations across all the filesystems on all the nodes of the GPFS cluster. Timeperiod is the only mandatory parameter for this graph.
    # cluster_open_close_operations    Retrieves the number of file open and close operations across all the filesystems on all the nodes of the GPFS cluster. Timeperiod is the only mandatory parameter for this graph.
    # cluster_read_write_latency       Retrieves the latency of file read and write operations across all the filesystems on all the nodes of the GPFS cluster. Timeperiod is the only mandatory parameter for this graph.
    # cluster_read_write_operations    Retrieves the number of file read and write operations across all the filesystems on all the nodes of the GPFS cluster. Timeperiod is the only mandatory parameter for this graph.

    # Check not implemented
    *) error_usage ;;
  esac

  # Execute remote command
  $rsh $query &> $tmp_file

  # Check SSH return code
  if [ $? -eq 255 ]; then error_login; fi

  # Check for performance center errors
  if grep -q 'EFSSG0002I' $tmp_file
  then
    echo "Error collecting performance data - check if performance center service is running using 'cfgperfcenter'"
    rm $tmp_file
    exit 3
  fi

  # Extract header and performance data from output
  header_raw=$(cat "$tmp_file" | head -n 1 | cut -d ',' -f 3-)
  perfdata_raw=$(cat "$tmp_file" | tail -n 1 | cut -d ',' -f 3- | sed 's/,/ /g')

  # Check extracted performance data
  if [ "$perfdata_raw" == "" ]
  then
    error_response $(cat "$tmp_file")
  fi

  # Initialize counter
  num_nodes=0

  # Compute performance data and output
  for i in $perfdata_raw
  do
    # Extract node's IP from header
    nodeindx=$(( num_nodes * 2 + 1 ))
    nodename=${nodenames["$(echo $header_raw | cut -d ',' -f $nodeindx | sed 's/\"//')"]}

    # Count number of nodes
    (( num_nodes += 1 ))

    case "$metric" in
      "cpu_utilization")
        # Calculate utilization from %idle
        utilization=$(echo "100-${i}" | bc)

        # Concatenate performance data per node
        perfdata="${perfdata} ${nodename}=${utilization}%;${warn_thresh};${crit_thresh};0;100"

        # Calculate max utilization for output
        if [ $(echo "${utilization}>${count_metric_1}" | bc) -eq 1 ]
        then
          count_metric_1=$utilization
        fi

        # Produce output
        output="Max. CPU utilization ${count_metric_1} %"

        # Calculate average utilization for output
        #sum_metric=$(echo "${sum_metric}+${utilization}" | bc)
        #output=$(echo "${sum_metric}/${num_nodes}" | bc)
        #output="Max. CPU utilization ${output}%"

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
      ;;
      "cpu_iowait")
        # Concatenate performance data per node
        perfdata="${perfdata} ${nodename}=${i}%;${warn_thresh};${crit_thresh};0;"

        # Calculate max utilization for output
        if [ $(echo "${i}>${count_metric_1}" | bc) -eq 1 ]
        then
          count_metric_1=$i
        fi

        # Produce output
        output="Max. IO Wait ${count_metric_1} %"

        # Calculate average utilization for output
        #sum_metric=$(echo "${sum_metric}+${i}" | bc)
        #output=$(echo "${sum_metric}/${num_nodes}" | bc)
        #output="Max. IO wait ${output}%"

        # Check if utilization is above threshold
        if [ $(echo "${i}>=${crit_thresh}" | bc) -eq 1 ] && [ "$return_code" -lt 2 ]
        then
          return_code=2
          return_status="CRITICAL"
        elif [ $(echo "${i}>=${warn_thresh}" | bc) -eq 1 ] && [ "$return_code" -lt 1 ]
        then
          return_code=1
          return_status="WARNING"
        fi
      ;;
      "public_network")
        # Report on send and receive throughput
        if [ "$repeat" -eq 2 ]
        then
          # First repeat - concatenate receive performance per node
          perfdata="${perfdata} ${nodename}_received=${i}B;${warn_thresh};${crit_thresh};0;"

          # Sum up throughput for output
          count_metric_1=$(echo "${count_metric_1}+${i}" | bc)
        else
          # Second repeat - concatenate send performance per node
          perfdata="${perfdata} ${nodename}_sent=${i}B;${warn_thresh};${crit_thresh};0;"

          # Sum up throughput for output
          count_metric_2=$(echo "${count_metric_2}+${i}" | bc)
        fi

        # Produce output
        output="Total received $(echo "scale=2; ${count_metric_1}/1024/1024" | bc) MB/s sent $(echo "scale=2; ${count_metric_2}/1024/1024" | bc) MB/s"

        # Check if throughput is above threshold
        if [ $(echo "${i}>=${crit_thresh}" | bc) -eq 1 ] && [ "$return_code" -lt 2 ]
        then
          return_code=2
          return_status="CRITICAL"
        elif [ $(echo "${i}>=${warn_thresh}" | bc) -eq 1 ] && [ "$return_code" -lt 1 ]
        then
          return_code=1
          return_status="WARNING"
        fi
      ;;
      "gpfs_throughput")
        # Report on read and write throughput
        if [ "$perfdata" == "" ]
        then
          # First metric - concatenate read performance
          perfdata=" read=${i}B;${warn_thresh};${crit_thresh};0;"

          # Produce output
          output="Total read $(echo "scale=2; ${i}/1024/1024" | bc) MB/s"
        else
          # Second metric - concatenate write performance
          perfdata="${perfdata} write=${i}B;${warn_thresh};${crit_thresh};0;"

          # Produce output
          output="${output} write $(echo "scale=2; ${i}/1024/1024" | bc) MB/s"
        fi

        # Check if throughput is above threshold
        if [ $(echo "${i}>=${crit_thresh}" | bc) -eq 1 ] && [ "$return_code" -lt 2 ]
        then
          return_code=2
          return_status="CRITICAL"
        elif [ $(echo "${i}>=${warn_thresh}" | bc) -eq 1 ] && [ "$return_code" -lt 1 ]
        then
          return_code=1
          return_status="WARNING"
        fi
      ;;
    esac

  done # for i in $perfdata_raw

  # Count repeats
  (( repeat -= 1 ))

done # while [ $repeat -gt 0 ]

# Cleanup
rm $tmp_file

# Produce Nagios output
echo "PERFDATA ${return_status} - ${output} |${perfdata}"
exit $return_code
