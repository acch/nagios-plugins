#!/bin/bash

###############################################################################
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

# Name:               Check OpenVZ Memory
# Author:             Achim Christ - achim(dot)christ(at)gmail(dot)com
# Version:            1.0
# Dependencies:       none
# Website:            https://github.com/acch/nagios-plugins

# This bash script checks memory usage of an OpenVZ container, and warns if it exceeds the amount of 'guaranteed RAM'.

# The actual code is managed in the following GitHub rebository - please use the Issue Tracker to ask questions, report problems or request enhancements.
# https://github.com/acch/nagios-plugins

# Disclaimer: This sample is provided 'as is', without any warranty or support. It is provided solely for demonstrative purposes - the end user must test and modify this sample to suit his or her particular environment. This code is provided for your convenience, only - though being tested, there's no guarantee that it doesn't seriously break things in your environment! If you decide to run it, you do so on your own risk!

mem_actual=$(grep privvmpages /proc/user_beancounters | awk '{print $3}')
mem_warn=$(grep vmguarpages /proc/user_beancounters | awk '{print $4}')
mem_crit=$(grep privvmpages /proc/user_beancounters | awk '{print $4}')
mem_max=$(grep privvmpages /proc/user_beancounters | awk '{print $5}')

if [ $mem_actual -gt $mem_warn ]; then retcode=1; msg="WARNING";
elif [ $mem_actual -gt $mem_crit ]; then retcode=2; msg="CRITICAL";
else retcode=0; msg="OK";
fi

mem_actual_mb=$(echo "scale=3; $mem_actual/250" | bc)
mem_warn_mb=$(echo "scale=3; $mem_warn/250" | bc)
mem_crit_mb=$(echo "scale=3; $mem_crit/250" | bc)
mem_max_mb=$(echo "scale=3; $mem_max/250" | bc)

echo "MEMORY $msg - ${mem_actual_mb}MB used currently | memused=${mem_actual_mb}MB;${mem_warn_mb};${mem_crit_mb};0;${mem_max_mb}"

exit $retcode
