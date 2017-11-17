#!/usr/local/bin/bash
#set -x

# -----------------------------------------------------------------------------
# File:		speed.sh - performance of computer <-> device eMMC <-> SD Card
#
# Usage:	./speed.sh
#
# Michael Sattler <michael@sattlers.org>
#
# https://github.com/mickeys/android-tools/blob/master/speed.sh?ts=4
#
# Details:	Iterate over TESTS[], capturing (and optionally massaging) output.
#			Add tests in the form "explanation ^ shell command", and perhaps a
#			tweak to the output section to get everything to print in the same
#			units (currently MB/s).
#
# -----------------------------------------------------------------------------

# =============================================================================
# SUPPORT
# =============================================================================
adb_res='.*pu..ed\. (.*/s )'			# matches "pushed" and "pulled" :-)
dd__res='.*\((.*) bytes/sec\)'			# grabs numeric part of dd output

# -----------------------------------------------------------------------------
# copy from to
# -----------------------------------------------------------------------------
copy() { dd if="$1" of="$2" bs=1M count=1024 ; }
# -----------------------------------------------------------------------------
# for better timing sync filesystem; clear caches
# -----------------------------------------------------------------------------
flush() { sh -c "sync && echo 3 > /proc/sys/vm/drop_caches" ; }

# =============================================================================
# PRE-REQUISITES
# =============================================================================
prerequisites() {
	adb root || { echo 'fatal error: "adb root" failed; quitting.' ; exit 1 ; }
	adb remount || { echo 'fatal error: "adb remount" failed; quitting.' ; exit 1 ; }

	# -------------------------------------------------------------------------
	# Find the attached device's SD card.
	# -------------------------------------------------------------------------
	__sd=$( adb shell df | \
		grep -e '/storage/.*' | grep -v 'emulated' | cut -f1 -d ' ' )
	if [ "${__sd}" == "" ];
	then
		echo "error: SD card not found; quitting."
		exit
	fi

	export __local=$( mktemp -d )		# properly get a temp workspace
	export __emmc=$( adb shell mktemp -d --tmpdir=/data ) # safe place to work

	# -------------------------------------------------------------------------
	# Create a 1GB file from a (non-compressible) movie source.
	#
	# Original plan was to use the built-in UNIX pseudo-random number generator
	#
	#     dd if=/dev/urandom of="the.file" bs=$fs count=1
	#
	# but that was unbearably slow, so I'm using a movie as source instead.
	# -------------------------------------------------------------------------
	big_source_movie="/Users/michael/Pictures/2016/07/20160724/20160724_211743.mov"
	fs=1G								# for actual performance tests
	fs=256M								# for smaller performance tests
	#fs='1K'							# for debugging this script
	echo "Creating $fs non-compressible file for moving around..."
	dd if="$big_source_movie" of="${__local}/the.file" bs=$fs count=1 >/dev/null 2>&1 \
		|| { echo 'fatal error: file create failed; quitting.' ; exit 1 ; }
}

# =============================================================================
# NOW ON TO THE TESTS
# =============================================================================
prerequisites							# ensure we have everything needed

declare -a TESTS=( \
	"computer ==> SD card ^ adb push ${__local}/the.file ${__sd}/the.file" \
	"computer <== SD card ^ adb pull ${__sd}/the.file ${__local}/1gb.sd.file" \
	"computer ==> eMMC ^ adb push ${__local}/the.file ${__emmc}/the.file" \
	"computer <== eMMC ^ adb pull ${__sd}/the.file ${__local}/1gb.emmc.file" \
	"SD Card ==> eMMC ^ adb shell dd if=${__sd}/the.file of=${__emmc}/from_sd.file" \
	"eMMC ==> SD Card ^ adb shell dd if=${__emmc}/from_sd.file of=${__sd}/the.file" \
)

# -----------------------------------------------------------------------------
# For pretty output, figure out the longest test description string.
# -----------------------------------------------------------------------------
max_len=0
test_parts='(.*) \^ (.*)'				# tests = "human part ^ shell command"
for i in "${TESTS[@]}"
do
	if [[ "$i" =~ $test_parts ]] ; then
		if [[ "${#BASH_REMATCH[1]}" > $max_len ]] ; then max_len="${#BASH_REMATCH[1]}" ; fi
	else
		echo "Error: couldn't understand \"$i\"; quitting."
	fi
done

printf '\nRESULTS\n'

# -----------------------------------------------------------------------------
# Now iterate and perform the tests
# -----------------------------------------------------------------------------
for i in "${TESTS[@]}"
do
	if [[ ! "$i" =~ $test_parts ]] ; then
		# For some reason the supplied string didn't match the requirements :-(
		echo "Error: couldn't understand \"$i\"; quitting."
	else
		# ---------------------------------------------------------------------
		# Break line into human- and computer-readable parts; execute command.
		# ---------------------------------------------------------------------
		printf "%-*s | " "$max_len" "${BASH_REMATCH[1]}"	# print human part
		cmd="${BASH_REMATCH[2]}"		# do any indirections
		x='${cmd}'						# second indirection; must be ' not "
		r=$( eval "$x" ) >/dev/null 2>&1 	# *do* the command; grap output

		# ---------------------------------------------------------------------
		# Make the output pretty ; add section for each new command type.
		# ---------------------------------------------------------------------
		is_adb='.*adb pu.*'				# command is 'adb pu{sh,ll}
		is_dd='.*adb shell dd'			# command is 'dd'

		if [[ "$cmd" =~ $is_adb ]] ; then
			if [[ "$r" =~ $adb_res ]] ; then echo "${BASH_REMATCH[1]}" ; else echo "ERROR: $r" ; fi
		elif [[ "$cmd" =~ $is_dd ]] ; then
			if [[ "$r" =~ $dd__res ]] ; then
				printf '%3.1f MB/s\n' $( bc <<< "scale=2; ${BASH_REMATCH[1]}/(1024*1024)" )
			else echo "ERROR: $r" ; fi
		else
			echo "$r"					# no special processing available
		fi
	fi
done

# -----------------------------------------------------------------------------
# Clean up
# -----------------------------------------------------------------------------
rm -rf "${__local}"
adb shell rm -rf "${__emmc}/"
