#!/bin/sh
#set -x

# -----------------------------------------------------------------------------
# Michael Sattler <michael@sattlers.org>
#
# https://github.com/mickeys/android-tools/blob/master/battstat.sh?ts=4
#
# Track battery level over time; save results in a a CSV file.
#
# The beauty of doing diagnostic capture this way is that now laptop need NOT
# be connected for the capture duration, and we can deploy this to any device,
# anywhere, and have it log battery data for an extended, arbitrary duration,
# under real-life working conditions, like in India during voting week.
#
# We can even bake this type of thing into our OS for automated health checks...
#
# Please read all the comments in this script; notes about how to graph results
# appear at the bottom.
#
# -----------------------------------------------------------------------------
# Setting up a device for testing & deploying the script

hw=$( getprop ro.product.model )		# string, like "twizzler"
if [[ "$hw" == "twizzler" ]] ; then		# writable (by both eng & user builds)
	_workdir="/storage/sdcard0/cid"
else
	_workdir="/sdcard/cid"
fi

_logdir="logs"							# where we store logfiles

# Cheat: here's all of the set-up steps in one easy to cut-and-paste line :-)
#
# 1. This does the set-up:
#adb shell svc power stayon true ; adb shell settings put system screen_brightness 128 ; _workdir="/sdcard/cid" ; _logdir="logs" ; adb shell mkdir -p $_workdir ; adb push battstat.sh $_workdir
# 2. This starts the job running. You can disconnect the device thereafter.
#adb shell (and then type) "sh $_workdir/battstat.sh &" (for remote execution)
# -----------------------------------------------------------------------------
#
# ------------------------------------------
# To set the device up for battery testing;
# this is just one standard to use.
# ------------------------------------------
# adb shell svc power stayon true		# keep screen on all the time
# adb shell settings put system screen_brightness 128	# half-brightness
#
# ------------------------------------------
# To deploy, from a connected laptop type the following 5 commands:
# ------------------------------------------

# adb shell mkdir -p $_workdir			# make necessary directory if missing
# adb push battstat.sh $_workdir		# push this file to the device
# adb shell "sh $_workdir/battstat.sh &"	# start this script running

# ------------------------------------------
# The results will be saved in a file named:
# ------------------------------------------

human_time=$( date +%Y%m%d_%H%M%S )		# human-readable easily-sorted time
sn=$( settings get secure android_id )	# this device's serial number
_logfile="$human_time-$hw-$sn-battstat.csv"	# logfile name

# Additionally, computational- or resource-heavy tasks are sandboxed to their
# own area, only executed every $m_interval times. Typically these don't change
# every $check_interval seconds, so there's no good reason to perturb the device
# under test too frequently.
#
# -----------------------------------------------------------------------------
# This script has been tested on Android 4.x and 7.x.
#
# Maintainers' note: Because this script is to run unattended on an Android
# 4.4.x system our *NIX are limited; no printf(), expr(), awk, nor sed.
# Before adding features check on your Android system; don't assume you
# have a complete Bourne Shell at your disposal.
# -----------------------------------------------------------------------------
_minute=60								# Not rocket science, but
_quarter_hour=$(( _minute * 15 ))		# just a little thing to
_half_hour=$(( _minute * 30 ))			# make this script a bit more
_hour=$(( _half_hour * 2 ))				# human-readable and a wee bit less
_day=$(( _hour * 24 ))					# prone to silly errors.
_week=$(( _day * 7 ))					# You're welcome.

check_interval=$_quarter_hour			# time between sampling, in seconds
m_interval=5							# do heavy tasks every $m_interval loops

start_time=$( date +%s )				# current time, since epoch, in seconds

# -----------------------------------------------------------------------------
# usage: get_keypair_value $keypair		# keypair is "name: value"
# -----------------------------------------------------------------------------
get_keypair_value() {
	args="$@"							# what's passed to us

	# -------------------------------------------------------------------------
	# The Android 4.4 Bourne Shell doesn't have much string manipulation, but
	# by tweaking the IFS we're able to extract the numeric keypair level from
	# the "name: value" that's returned to us by dumpsys. Yay!
	# -------------------------------------------------------------------------
	oldIFS=$IFS							# capture existing int'l field separator
	IFS=' '								# ' ' is delimiter in "level: 99"
	set -- $args						# set input target
	f1=$1								# capture "level:"
	keypair_value=$2					# capture the numeric value part
	IFS=$oldIFS							# restore the IFS
}

mkdir -p "$_workdir" "$_workdir/$_logdir"	# create necessary directories
_r=$?
echo mkdir return code is $_r "$_workdir/$_logdir"

# -----------------------------------------------------------------------------
# Generate a unique, sortable filename for this data collection event.
# -----------------------------------------------------------------------------
exec 3<> "$_workdir/$_logdir/$_logfile"	# open up log with file descriptor 3
_r=$?
echo exec 3 return code is $_r

# write out column header info
_column_names="human time, battery level, elapsed_time_secs, elapsed_time_mins, elapsed_time_hours, battery health, battery status, battery temperature"
echo "$_column_names"					# write to stdout
echo "$_column_names" >&3				# write to logfile

m_counter=0								# modulus counter

while [ 1 ]								# loop forever until battery shutdown
do
	# -------------------------------------------------------------------------
	# In a perfect world I'd grab a %s timestamp and then convert it into human-
	# readable forms, but this version of `date` can't. So we'll have to suffer
	# the tiny time delay between these two commands...
	# -------------------------------------------------------------------------
	now=$( date +%s )					# current time, since epoch, in seconds

	# -------------------------------------------------------------------------
	# As I play with graphing the battery level output I see that sometimes the
	# resolution is too high and makes for confusing graphs. The question most
	# ask are "how many hours does the battery last?" So I'm reporting elapsed
	# time in seconds, minutes, and hours until we come to an understanding of
	# what's really useful (vs what takes up unnecessary space on the device).
	# -------------------------------------------------------------------------
	elapsed_time_secs=$(( now - start_time ))			# seconds
	elapsed_time_mins=$(( elapsed_time_secs / 60 ))		# minutes
	elapsed_time_hours=$(( elapsed_time_mins / 60 ))	# hours

	human_time=$( date +"%m/%d/%Y %H:%M" )	# Google Sheets preferred format
	# ^^^^^^^^^^^
	# After playing with graphing battery data for a while, it seems that having
	# time resolved to the second just makes for messy charts. So I've gone to
	# reporting HH:MM. If you want seconds just add ":%S" to the format string.

	battstats=$( dumpsys battery )		# get stats for multiple extractions

	# -------------------------------------------------------------------------
	# battery charge level, in percent
	# -------------------------------------------------------------------------
	b_str=$( echo "$battstats" | grep level )
	get_keypair_value "$b_str"			# "level: 99" --> "99"
	b_level="$keypair_value"			# save the value for printing

	# -------------------------------------------------------------------------
	# For tasks that don't change frequently enough to matter recording each
	# pass through this loop, or for those tasks which are computationally
	# or resource heavy-weight we process only every $m_interval times.
	#
	# We write the CSV log with null values so graphing will still work.
	# -------------------------------------------------------------------------
	mod_pass=$(( m_counter % m_interval ))	# for i=5: 0, 5, 10, 15, ...
	if [ $mod_pass -eq 0 ]
	then
		# ---------------------------------------------------------------------
		# battery health
		# ---------------------------------------------------------------------
		b_str=$( echo "$battstats" | grep health )
		get_keypair_value "$b_str"		# "health: 99" --> "99"
		b_health="$keypair_value"		# save the value for printing

		case $(( b_health )) in
			1)  b_health="unknown"
				;;
			2)  b_health="good"
				;;
			3)  b_health="overheat"
				;;
			4) b_health="dead"
			   ;;
			5) b_health="over-voltage"
			   ;;
			6) b_health="unspecified"
			   ;;
			7) b_health="cold"
			   ;;
			*) b_health="error($b_health)"
			   ;;
		esac

		# ---------------------------------------------------------------------
		# battery status
		# 1 Unknown 2 Charging 3 Discharging 4 Not charging 5 Full
		# ---------------------------------------------------------------------
		b_str=$( echo "$battstats" | grep status )
		get_keypair_value "$b_str"		# "status: 99" --> "99"
		b_status="$keypair_value"		# save the value for printing

		case $(( b_status )) in
			1)  b_status="unknown"
				;;
			2)  b_status="charging"
				;;
			3)  b_status="discharging"
				;;
			4) b_status="not charging"
			   ;;
			5) b_status="full"
			   ;;
			*) b_status="error($b_status)"
			   ;;
		esac

		# ---------------------------------------------------------------------
		# battery temperature / 10 = degrees C
		# ---------------------------------------------------------------------
		b_str=$( echo "$battstats" | grep temperature )
		get_keypair_value "$b_str"		# "temperature: 99" --> "99"
		b_temp=$(( keypair_value / 10 ))	# save the value for printing
	else
		b_health=''						# write null value to the CSV logfile
		b_status=''						# write null value to the CSV logfile
		b_temp=''						# write null value to the CSV logfile
	fi

	# -------------------------------------------------------------------------
	# Assemble the data for output
	# -------------------------------------------------------------------------
	outstr="$human_time, $b_level, $elapsed_time_secs, $elapsed_time_mins, $elapsed_time_hours, $b_health, $b_status, $b_temp"
	echo "$outstr"						# write to stdout
	echo "$outstr" >&3					# write to logfile
	sync								# flush everything to disk

	# -------------------------------------------------------------------------
	# At some interval the frequency of checking will impact battery longevity,
	# which is what we're testing, but chatter around the office is that likely
	# any interval > 1/minute is okay. Will test this out sometime...
	# -------------------------------------------------------------------------
	m_counter=$(( m_counter + 1 ))		# take note of this pass
	sleep $check_interval				# delay until next measurement, in secs
done

# -----------------------------------------------------------------------------
# Interpretation of the results can be done by examining the CSV file directly
# or graphing them. I've found that importing the data into sheets.google.com
# and tweaking the line graph settings makes for a reasonably satisfying output.
# -----------------------------------------------------------------------------
