#!/bin/bash

# Source: https://exchange.nagios.org/directory/Plugins/Others/Check-Path-Age/details

CHECK_PATH=$1
WARNING=$2
CRITICAL=$3
SORT=$4
EXIST=$5
DIG=$6

######################
## CHECK FOR ERRORS ##
######################
if [ "$6" == "" ]; then
        echo "Usage: check_path_age.sh <PATH> <WARNING_MINUTES> <CRITICAL_MINUTES> <oldest|newest> <exist|noexist> <dig|nodig>"
        exit 3
fi

if [ $WARNING -le 0 ]; then
        echo "WARNING must be greater than 0 minutes."
        exit 3
fi

if [ $CRITICAL -le 0 ]; then
        echo "CRITICAL must be greater than 0 minutes."
        exit 3
fi

if [ $WARNING -gt $CRITICAL ]; then
	echo "WARNING must be less than or equal to CRITICAL."
	exit 3
fi

if [ $SORT != "oldest" ]; then
	if [ $SORT != "newest" ]; then
		echo "You must specify 'oldest' or 'newest' to sort the files."
		exit 3
	fi
fi

if [ $EXIST != "exist" ]; then
	if [ $EXIST != "noexist" ]; then
		echo "You must specify 'exist' or 'noexist' to determine if the path must exist."
		exit 3
	fi
fi

if [ $DIG != "dig" ]; then
	if [ $DIG != "nodig" ]; then
		echo "You must specify 'dig' or 'nodig' to determine whether or not to search subdirectories."
		exit 3
	fi
fi

##########################
## CHECK IF PATH EXISTS ##
##########################
if [ $EXIST == "exist" ]; then
	if [ ! -e "$CHECK_PATH" ]; then
		echo "CRITICAL - '$CHECK_PATH' does not exist."
		exit 2
	fi
else
	if [ ! -e "$CHECK_PATH" ]; then
		echo "OK - '$CHECK_PATH' does not exist."
		exit 0
	fi
fi

#######################
## CHECK AGE OF PATH ##
#######################
if [ $SORT == "oldest" ]; then
	if [ $DIG == "dig" ]; then
		FILE=`find $CHECK_PATH -type f -mmin +$CRITICAL -print -quit`
	else
		FILE=`find $CHECK_PATH -maxdepth 1 -type f -mmin +$CRITICAL -print -quit`
	fi
	if [ -n "$FILE" ]; then
		echo "CRITICAL - '$CHECK_PATH' is older than $CRITICAL minutes."
	        exit 2
	fi

	if [ $DIG == "dig" ]; then
		FILE=`find $CHECK_PATH -type f -mmin +$WARNING -print -quit`
	else
		FILE=`find $CHECK_PATH -maxdepth 1 -type f -mmin +$WARNING -print -quit`
	fi
	if [ -n "$FILE" ]; then
                echo "WARNING - '$CHECK_PATH' is older than $WARNING minutes."
                exit 1
	else
		echo "OK - '$CHECK_PATH' is newer than $WARNING minutes."
		exit 0
        fi
else
	if [ $DIG == "dig" ]; then
		FILE=`find $CHECK_PATH -type f -mmin -$CRITICAL -print -quit`
	else
		FILE=`find $CHECK_PATH -maxdepth 1 -type f -mmin -$CRITICAL -print -quit`
	fi
        if [ -z "$FILE" ]; then
                echo "CRITICAL - '$CHECK_PATH' is older than $CRITICAL minutes."
                exit 2
        fi

	if [ $DIG == "dig" ]; then
	        FILE=`find $CHECK_PATH -type f -mmin -$WARNING -print -quit`
	else
		FILE=`find $CHECK_PATH -maxdepth 1 -type f -mmin -$WARNING -print -quit`
	fi
        if [ -z "$FILE" ]; then
                echo "WARNING - '$CHECK_PATH' is older than $WARNING minutes."
                exit 1
	else
		echo "OK - '$CHECK_PATH' is newer than $WARNING minutes."
                exit 0
        fi
fi
