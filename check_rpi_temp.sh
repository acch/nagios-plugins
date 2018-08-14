#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2018 Achim Christ                                              #
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

# Name:               Check Raspberry Pi Temperature
# Author:             Achim Christ - achim(dot)christ(at)gmail(dot)com
# Version:            1.0
# Website:            https://github.com/acch/nagios-plugins

# This bash script reports on and checks CPU and GPU temperature of the local Rapsberry Pi single-board computer, and warns if it exceeds the thresholds.
# The plugin produces Nagios performance data so it can be graphed.

# The actual code is managed in the following GitHub rebository - please use the Issue Tracker to ask questions, report problems or request enhancements.
#   https://github.com/acch/nagios-plugins

# Disclaimer: This sample is provided 'as is', without any warranty or support. It is provided solely for demonstrative purposes - the end user must test and modify this sample to suit his or her particular environment. This code is provided for your convenience, only - though being tested, there's no guarantee that it doesn't seriously break things in your environment! If you decide to run it, you do so on your own risk!

# Version History:
# 1.0    9.8.2018     Initial Release

#####################
### Configuration ###
#####################

# Warning threshold (degree celsius)
warn_thresh=60  # This is the default which can be overridden with commandline parameters
# Critical threshold (degree celsius)
crit_thresh=70  # This is the default which can be overridden with commandline parameters

####################################
### Do not edit below this line! ###
####################################

error_usage () {
  echo "Usage: $0 [-w <warning_threshold>] [-c <critical_threshold>]"
  exit 3
}

# Check commandline options
while getopts 'w:c:' OPT; do
  case $OPT in
    w) warn_thresh=$OPTARG ;;
    c) crit_thresh=$OPTARG ;;
    *) error_usage ;;
  esac
done

#################
# Sanity checks #
#################

# Check if thresholds are numbers
if ! [[ "$warn_thresh" =~ ^[[:digit:]]+$ ]] || ! [[ "$crit_thresh" =~ ^[[:digit:]]+$ ]] ; then error_usage ; fi

# Check for vcgencmd
if [ ! -x /opt/vc/bin/vcgencmd ]
then
  echo "'/opt/vc/bin/vcgencmd' not found - is this a Raspberry Pi?"
  exit 3
fi

# Initialize return code
return_code=0
return_status="OK"

#####################
# Check temperature #
#####################

# Read temperature information
cpu=$(</sys/class/thermal/thermal_zone0/temp)
gpu=$(/opt/vc/bin/vcgencmd measure_temp | sed -e "s/temp=//" -e "s/'C//")
printf -v gpuint %.0f "$gpu"  # Round GPU temperature to integer

# Check for errors
if [ "$cpu" -gt $((crit_thresh*1000)) ] || [ "$gpuint" -gt "$crit_thresh" ]
then
  # Temperature above critical threshold
  return_code=2
  return_status="CRITICAL"
# Check for warnings
elif [ "$cpu" -gt $((warn_thresh*1000)) ] || [ "$gpuint" -gt "$crit_thresh" ]
then
  # Temperature above warning threshold
  return_code=1
  return_status="WARNING"
fi

# Produce Nagios output
echo "TEMP ${return_status} - CPU temperature: $((cpu/1000)).$((cpu%1000))°C - GPU temperature: ${gpu}°C | cputemp=$((cpu/1000)).$((cpu%1000));${warn_thresh};${crit_thresh};0; gputemp=${gpu};${warn_thresh};${crit_thresh};0;"
exit $return_code
