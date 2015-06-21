#!/bin/bash
#
# TelstraSmsApiBashScript
# github.com/timiscoding
# Uses the Telstra SMS API to send and receive text messages from any Australian mobile. 
#
# Global variables
# 		KEY_FILE	stores key/secret, token and expiry time
#		DATA_FILE	stores message id and outbound sms data
#		APP_KEY			
#		APP_SECRET
#		TOKEN		auth token for app key/secret
#		TOKEN_EXPIRE	token expiry time in seconds from epoch. ie. token creation time + TOKEN_INTERVAL
#		TOKEN_INTERVAL	time in seconds token is valid. Set slightly shorter than APIs "expire_in" time in case clock is slower than server time
#		SCREEN_TITLE	top bar text on menu
#		SCREEN_PROMPT	text shown to user. eg. menus and options
# 		RETURN_VAL	return value from function
#
NTA='\033[0m' 				# No text attributes
BOLD_RED='\033[31;1;40m'  
INV='\033[47;30m' 			# dark grey background, white text
BOLD='\033[7m'
BOLD_GREEN='\033[32;1;40m'
BOLD_YELLOW='\033[33;1;40m'
SAVE_TERM="$(stty -g)"			# save term settings 

############
# Make Telstra API call to send a text message
# Globals: 
# 		RETURN_VAL
# Arguments:
# 		phone
# Returns:
# 		1: on server timeout
# 		2: message not sent due to server error
############
sendText() {
	checkToken || return 1
	local phone=$1
	local msg=$(echo "$2" | sed 's/"/\\\"/g')		# double quotes need to be escaped for JSON 
	local resp=$(
		curl --connect-timeout 5 -m 5 -s -H "Content-Type: application/json" \
		-H "Authorization: Bearer $TOKEN" \
		-d "{\"to\":\"$phone\", \"body\":\"$msg\"}" \
		"https://api.telstra.com/v1/sms/messages") 
	[ $? -ne 0 ] && return 1
	local server_status=$(echo "$resp" | grep -Po "status\":\s\K\d+")
	local server_msg=$(echo "$resp" | grep -Po "message\":\s\K[\w\s]+")
	local msg_id=$(echo "$resp" | grep -Po "messageId\":\"\K\w+")
	if [ -n "$msg_id" ] ; then
		RETURN_VAL="$msg_id"
	else
		RETURN_VAL="${server_status} ${server_msg}"
		return 2
	fi
}

############
# Make Telstra API call to get delivery status for a message
# Globals:
# 		RETURN_VAL
# Arguments:
# 		id - Message ID
# Returns:
#		1: on server timeout
# 		2: no delivery status retrieved
############
checkStatus() {
	checkToken || return 1
	RETURN_VAL=
	local id=$1
	local resp=$(curl --connect-timeout 5 -m 5 -sH "Authorization: Bearer $TOKEN" "https://api.telstra.com/v1/sms/messages/$id")
	[ $? -ne 0 ] && return 1
	local ph=$(echo "$resp" | grep -Po "to\":\"\K\d+" | sed s/^61/0/)
	local received=$(echo "$resp" | grep -Po "receivedTimestamp\":\"\K[\w:-]+")
	local sent=$(echo "$resp" | grep -Po "sentTimestamp\":\"\K[\w:-]+")
	local status=$(echo "$resp" | grep -Po "status\":\"\K\w+")
	if [ -n "$status" ] ; then
		RETURN_VAL="$(printf "%10s | %19s | %19s | %s\n" "$ph" "$received" "$sent" "$status")"
	else
		return 2
	fi
}

###########
# Make Telstra API call to get reply from message ID
# Globals:
# 		RETURN_VAL
# Arguments:
# 		id - message ID
# Returns:
# 		1: on server timeout
# 		2: no reply retrieved
###########
checkResponse() {
	checkToken || return 1
	RETURN_VAL=
	local id=$1
	local resp=$(curl --connect-timeout 5 -m 5 -sH "Authorization: Bearer $TOKEN" "https://api.telstra.com/v1/sms/messages/$id/response")
	[ $? -ne 0 ] && return 1
	local ph=$(echo "$resp" | grep -Po "from\":\"\K\d+" | sed s/^61/0/)
	local date=$(echo "$resp" | grep -Po "Timestamp\":\"\K[\w:-]+")
	local content=$(echo "$resp" | grep -Po "content\":\"\K.+(?=\")")
	if [ -n "$date" ] ; then
		RETURN_VAL="$(printf "%10s | %19s | %s\n" "$ph" "$date" "$content")"
	else
		return 2
	fi	
}

##########
# Display top bar, menu, options
# Globals:
# 		SCREEN_TITLE
#		SCREEN_PROMPT
# Arguments:
# 		None
# Returns:
# 		None
##########
showScreen() {
	local cols=$(stty size | cut -d' ' -f2)
	local name="Telstra Sms Api Bash script"
	printf "\033c\r" # clears screen. compatible with VT100 terminals
	printf "${INV}%-*s%s\n${NTA}" $(($cols - ${#name})) "$SCREEN_TITLE" "$name" # top bar
	printf "%0.s=" $(seq 1 $cols) # print upper border
	printf '\n\n'
	printf "$SCREEN_PROMPT\n" | sed 's/^/ /'
	echo
	printf "%0.s=" $(seq 1 $cols) # print upper border
}

###########
# Get user input for phone/message/message ID
# Globals:
# 		RETURN_VAL
# Arguments:
# 		type - type of user input
# 		text - initial editable user input text
# 		prompt - text to show before waiting for input
# Returns:
# 		None
###########
getInput() {
	local type=$1
	local text=$2		 
	local prompt=$3	
	case $type in
		PH)
			read -p "$prompt" -i "$text" -e RETURN_VAL
		;;
		MSG)
			while true ; do
				echo "$prompt"
				read -r -i "$text" -e RETURN_VAL
				if [ ${#RETURN_VAL} -gt 160 ] ; then
					text="$RETURN_VAL"
					showScreen
					printf "${BOLD_RED}Message has ${#RETURN_VAL} characters${NTA}\n"
				else
					break 
				fi
			done
		;;
		ID)
			read -p "$prompt" -i "$text" -e RETURN_VAL
		;;
	esac
}

##########
# Menu option for sending text message
# Globals:
# 		SCREEN_TITLE
# 		SCREEN_PROMPT
# 		BOLD
# 		NTA
# 		BOLD_YELLOW
# 		BOLD_RED
# 		BOLD_GREEN
# 		DATA_FILE
# 		RETURN_VAL
# Arguments:
# 		None
# Returns:
# 		None
##########
optSendText() {
	SCREEN_TITLE="Send Text"
	local s1="1. Enter mobile"
	local s2="2. Enter message"
	local s3="3. Confirmation screen"
	SCREEN_PROMPT="${BOLD}${s1}${NTA}\n${s2}\n${s3}\n\n b) Back to main menu"
	local ph
	local msg
	local res	# message ID result
	local return_code
	showScreen
	getInput PH "" "Enter mobile:"
	ph="$RETURN_VAL"
	[ "$ph" = b ] && return
	SCREEN_PROMPT="${s1}\n${BOLD}${s2}${NTA}\n${s3}"
	showScreen
	getInput MSG "" "Enter text message (160 char limit):"
	msg="$RETURN_VAL"
	while true ; do
		SCREEN_PROMPT="${s1}\n${s2}\n${BOLD}${s3}${NTA}\n\n\tMobile: [$ph]\n\tMessage: [$msg]\n\nChoose:\n1) edit mobile\t2) edit message\t3) send text\t4) back to main menu"
		showScreen
		read -p "Choice:" choice
		case $choice in
			1)
				showScreen
				getInput PH $ph "Edit mobile:"
				ph="$RETURN_VAL"
				continue
			;;
			2)
				showScreen
				getInput MSG "$msg" "Edit message (160 char limit):"
				msg="$RETURN_VAL"
				continue
			;;
			3)
				SCREEN_PROMPT="${BOLD_YELLOW}Sending text ...${NTA}"
				showScreen
				sendText "$ph" "$msg"
				return_code=$?
				res="$RETURN_VAL"
				if [ $return_code -eq 2 ] ; then
					SCREEN_PROMPT="${BOLD_RED}Server error $res${NTA}\n\nPress ENTER to return"
					showScreen
					read REPLY
					continue
				elif [ $return_code -eq 1 ] ; then
					SCREEN_PROMPT="${BOLD_RED}Server timeout${NTA}\n\nPress ENTER to return"
					showScreen
					read REPLY
					continue
				fi
				echo "$res|$ph" >> "$DATA_FILE"
				echo "OUTBOUND|$ph|$(date +"%s" | cut -c1-19)|$msg" >> "$DATA_FILE"
				SCREEN_PROMPT="${BOLD_GREEN}Message sent.${NTA} To check status/response, use message id:\n\n\t${res}\n\nIt has been added to file ${DATA_FILE}. Press ENTER to return"
				showScreen
				read REPLY
				break
			;;
			4)
				break
			;;
		esac
	done
}

###########
# Menu option for checking message delivery status
# Globals:
# 		SCREEN_TITLE
# 		SCREEN_PROMPT
# 		RETURN_VAL
# 		BOLD_YELLOW
# 		NTA
# 		BOLD_RED
# Arguments:
# 		None
# Returns:
# 		None 		
###########
optStatus() {
	local msg_id
	local res		# delivery status result
	local opt		# key pressed option
	local return_code
	SCREEN_TITLE="Check Status"
	while true ; do
		SCREEN_PROMPT="Check the delivery status of a single text message by entering its message id.\n\n\tb) Back to main menu"
		showScreen
		getInput ID "$msg_id" "Enter message id:"
		msg_id="$RETURN_VAL"
		[ -z "$msg_id" ] && continue
		[ "$msg_id" = b ] && break
		SCREEN_PROMPT="Delivery status for message id: $msg_id\n\n${BOLD_YELLOW}Checking id...${NTA}"
		showScreen
		checkStatus $msg_id
		return_code=$?
		res="$RETURN_VAL"
		if [ $return_code -eq 0 ] ; then
			SCREEN_PROMPT="Delivery status for message id: $msg_id\n\n$(printf "%-10s | %-19s | %-19s | %s" "Mobile" "Received" "Sent" "Status")\n$res\n\n1) Go back\t2) Back to main menu"
		elif [ $return_code -eq 1 ] ; then
			SCREEN_PROMPT="${BOLD_RED}Server timeout${NTA}\n\n1) Go back\t2) Back to main menu"
		elif [ $return_code -eq 2 ] ; then
			SCREEN_PROMPT="Delivery status for message id: $msg_id\n\n${BOLD_RED}No results. Please check message id.${NTA}\n\n1) Go back\t2) Back to main menu"
		fi				 
		while true ; do
			showScreen
			read -p "Choice:" opt
			case "$opt" in
				1) continue 2;;
				2) break 2;;
			esac
		done
	done
}

############
# Menu option for checking a reply to a message ID
# Globals:
# 		SCREEN_TITLE
# 		SCREEN_PROMPT
# 		BOLD_YELLOW
# 		BOLD_RED
# 		NTA
# 		DATA_FILE
# 		RETURN_VAL
# Arguments:
# 		None
# Returns: 		
# 		None
############
optResponse() {
	local msg_id
	local res
	local msg
	local ph
	local date
	local return_code
	SCREEN_TITLE="Check response"
	while true ; do
		SCREEN_PROMPT="Check whether a reply has been sent back by entering the message id.\n\nb) Back to main menu"
		showScreen
		getInput ID "$msg_id" "Enter message id:"
		msg_id="$RETURN_VAL"
		[ -z "$msg_id" ] && continue
		[ "$msg_id" = b ] && break
		SCREEN_PROMPT="Response status for message id: $msg_id\n\n${BOLD_YELLOW}Checking id...${NTA}"
		showScreen
		res=$(cat "$DATA_FILE" | grep "$msg_id")
		msg=$(echo "$res" | cut -d'|' -f4) # find reply from file
		if [ -z "$msg" ] ; then # reply not in file
			checkResponse "$msg_id"
			return_code=$?
			if [ $return_code -eq 0 ] ; then
				res="$RETURN_VAL"
				date=$(echo "$res" | cut -d'|' -f2 | sed s/\s//g)
				date=$(date -d $date +%s)
				msg=$(echo "$res" | cut -d'|' -f3 | cut -c2-)
				sed -r -iOLD "s/${msg_id}.*/&\|$date\|$msg/" "$DATA_FILE"
			elif [ $return_code -eq 1 ] ; then
				SCREEN_PROMPT="${BOLD_RED}Server timeout${NTA} Press ENTER to return"
				showScreen
				read REPLY
				continue
			elif [ $return_code -eq 2 ] ; then
				SCREEN_PROMPT="Response status for message id: $msg_id\n\n${BOLD_RED}No results. Please check message id.${NTA}\n\n1)Go back\t2) Back to main menu"				 
			fi
		else # reply in file
			ph=$(echo "$res" | cut -d'|' -f2)
			date=$(echo "$res" | cut -d'|' -f3)
			date=$(date -d @$date +%Y-%m-%dT%H:%M:%S) # convert time field to human readable format
			res=$(printf "%10s | %19s | %s" "$ph" "$date" "$msg")
		fi
		if [ -n "$res" ] ; then
			SCREEN_PROMPT="Response status for message id: $msg_id\n\n$(printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message")\n$res\n\n1)Go back\t2) Back to main menu"
		fi
		while true ; do
			showScreen
			read -p "Choice:" opt
			case "$opt" in
				1) continue 2;;
				2) break 2;;
			esac
		done

	done
}

#############
# Menu option to check delivery status for all message ids stored in file DATA_FILE
# Globals:
# 		SCREEN_TITLE
# 		SCREEN_PROMPT
# 		DATA_FILE
# 		SAVE_TERM
# 		BOLD_RED
# 		BOLD_YELLOW
# 		NTA
# 		RETURN_VAL
# Arguments:
# 		None
# Returns:
# 		None 		 		
#############
optStatuses() {
	local msg_ids
	local msg_id_count
	local res		# status for a single message
	local all_res	# statuses for all messages
	local i=0		# progress counter for getting statuses
	local res_count=0		# number of results found
	local key				# keypress
	local return_code
	SCREEN_TITLE="Check All Statuses"
	msg_ids=$(cat "$DATA_FILE" | cut -d'|' -f1 | grep -v OUTBOUND)
	msg_id_count=$(echo "$msg_ids" | sed '/^$/d' | wc -l)
	if [ -t 0 ] ; then stty -echo -icanon time 0 min 0; fi		# set non-blocking user input
	for id in $msg_ids ; do
		key=$(cat 2>/dev/null)	# read user input. redirect to /dev/null is to stop 'resource temporarily unavail' error in cygwin
		if echo "$key" | grep c ; then		# user wants to cancel operation
			if [ -t 0 ] ; then stty $SAVE_TERM; fi
			SCREEN_PROMPT="Checking all statuses in file ${DATA_FILE}\n\nProcessed message ID $i / $msg_id_count\n\n$(printf "%-10s | %-19s | %-19s | %s\n" "Mobile" "Received" "Sent" "Status")\n$all_res\n\n${BOLD_RED}Operation cancelled.${NTA} Press ENTER to go back to main menu"
			showScreen
			read REPLY
			return
		fi
		i=$((i + 1))
		checkStatus $id
		return_code=$?
		res="$RETURN_VAL"
		if [ $return_code -eq 0 ] ; then
			res_count=$((res_count + 1))
			all_res="$all_res$res\n"
			SCREEN_PROMPT="Checking all statuses in file ${DATA_FILE}\n\n${BOLD_YELLOW}Processed message ID $i / $msg_id_count\t\tc) Cancel operation${NTA}\n\n$(printf "%-10s | %-19s | %-19s | %s\n" "Mobile" "Received" "Sent" "Status")\n$all_res"
			showScreen
		elif [ $return_code -eq 1 ] ; then
			SCREEN_PROMPT="Checking all statuses in file ${DATA_FILE}\n\n${BOLD_YELLOW}Processed message ID $i / $msg_id_count\t\tc) Cancel operation${NTA}\n\n$(printf "%-10s | %-19s | %-19s | %s\n" "Mobile" "Received" "Sent" "Status")\n$all_res${BOLD_RED}Server timeout${NTA}"
			showScreen
		elif [ $return_code -eq 2 ] ; then
			SCREEN_PROMPT="Checking all statuses in file ${DATA_FILE}\n\n${BOLD_YELLOW}Processed message ID $i / $msg_id_count\t\tc) Cancel operation${NTA}\n\n$(printf "%-10s | %-19s | %-19s | %s\n" "Mobile" "Received" "Sent" "Status")\n$all_res${BOLD_RED}No result for ID $id${NTA}"
			showScreen
		fi
	done 
	if [ -t 0 ] ; then stty $SAVE_TERM; fi
	if [ $res_count -gt 0 ] ; then
		SCREEN_PROMPT="Found $res_count results from $msg_id_count message IDs:\n\n$(printf "%-10s | %-19s | %-19s | %s\n" "Mobile" "Received" "Sent" "Status")\n$all_res\nPress ENTER to return"
	else
		SCREEN_PROMPT="Found 0 results from $msg_id_count message IDs.\n\nPress ENTER to return"
	fi
	showScreen
	read REPLY				 
}

#############
# Menu option for checking replies to all message ids in file DATA_FILE
# Globals:
# 		SCREEN_TITLE
# 		SCREEN_PROMPT
# 		DATA_FILE
# 		BOLD_RED
# 		BOLD_YELLOW
# 		NTA
# 		RETURN_VAL
# 		SAVE_TERM 		
# Arguments:
# 		None
# Returns:
# 		None
#############
optResponses() {
	local msg_ids
	local msg_id_count
	local res		# reply for a single message
	local all_res	# replies for all messages
	local i=0		# progress counter when getting all replies
	local res_count=0		# number of replies found
	local key				# keypress
	local return_code
	SCREEN_TITLE="Check All Responses"
	msg_ids=$(cat "$DATA_FILE" | cut -d'|' -f1 | grep -v OUTBOUND)
	msg_id_count=$(echo "$msg_ids" | sed '/^$/d' | wc -l)
	if [ -t 0 ] ; then stty -echo -icanon time 0 min 0; fi
	for id in $msg_ids ; do
		key="$(cat 2>/dev/null)"
		if echo "$key" | grep c ; then
			if [ -t 0 ] ; then stty $SAVE_TERM; fi
			SCREEN_PROMPT="Processed $i / $msg_id_count message IDs:\n\n$(printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message")\n$all_res\n\n${BOLD_RED}Operation cancelled. ${NTA}Press ENTER to return to main menu"
			showScreen
			read REPLY
			return
		fi
		i=$((i + 1))
		res=$(cat "$DATA_FILE" | grep "$id")
		msg=$(echo "$res" | cut -d'|' -f4) # find reply from file
		if [ -z "$msg" ] ; then # reply not in file
			checkResponse "$id"
			return_code=$?
			res="$RETURN_VAL"
			if [ $return_code -eq 1 ] ; then
				SCREEN_PROMPT="${BOLD_YELLOW}Processed messaged ID $i / $msg_id_count\t\t c) Cancel operation${NTA}\n\n$(printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message")\n$all_res${BOLD_RED}Server timeout${NTA}"
				showScreen
			elif [ $return_code -eq 2 ] ; then
				continue
			fi
			date=$(echo "$res" | cut -d'|' -f2 | sed s/\s//g)
			date=$(date -d "$date" +"%s")
			msg=$(echo "$res" | cut -d'|' -f3 | cut -c2-)
			sed -r -iOLD "s/${id}.*/&\|$date\|$msg/" "$DATA_FILE"
		else # reply in file
			ph=$(echo "$res" | cut -d'|' -f2)
			date=$(echo "$res" | cut -d'|' -f3)
			date=$(date -d @$date +%Y-%m-%dT%H:%M:%S) # convert time field to human readable format
			res=$(printf "%10s | %19s | %s" "$ph" "$date" "$msg")
		fi
		if [ -n "$res" ] ; then
			res_count=$((res_count + 1))
			all_res="$all_res$res\n"
			SCREEN_PROMPT="${BOLD_YELLOW}Processed messaged ID $i / $msg_id_count\t\t c) Cancel operation${NTA}\n\n$(printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message")\n$all_res"
			showScreen
		fi
	done
	if [ -t 0 ] ; then stty $SAVE_TERM; fi
	if [ $res_count -gt 0 ] ; then
		SCREEN_PROMPT="Found $res_count results from $msg_id_count message IDs:\n\n$(printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message")\n$all_res\nPress ENTER to return"
	else
		SCREEN_PROMPT="Found 0 replies from $msg_id_count message IDs.\n\nPress ENTER to return"
	fi
	showScreen
	read REPLY				 
}

#############
# Menu option for returning all inbound/outbound messages in chronological order for a given mobile
# Globals:
# 		OIFS - old internal field separator
# 		IFS
# 		SCREEN_TITLE
#		SCREEN_PROMPT
# 		RETURN_VAL
# 		DATA_FILE
# 		BOLD_YELLOW
# 		NTA
# 		BOLD_RED
# 		SAVE_TERM
# Arguments:
# 		None
# Returns:
# 		None
#############
optMessageChain() {
	local ph
	local rows			# a row in DATA_FILE
	local row_count
	local i				# progress counter when getting messages
	local msg_id
	local date			# date of message
	local msg
	local resp			# response from telstra api 
	local sorted		# all messages sorted by time 
	local dir			# inbound/outbound direction
	local res			
	local all_res		
	local key			# keypress for cancelling operation
	local unsorted		
	local return_code
	OIFS=$IFS
	IFS=$'\n'
	while true ; do
		unsorted=
		all_res=
		i=0
		SCREEN_TITLE="Check Message Chain"
		SCREEN_PROMPT="Retrieve a chronological sorted list of inbound and outbound messages.\n\nb) Back to main menu"
		showScreen
		getInput PH "$ph" "Enter mobile:"
		ph="$RETURN_VAL"
		[ -z "$ph" ] && continue;
		[ "$ph" = b ] && break;
		rows=$(cat "$DATA_FILE" | grep -P "[^\|]+\|$ph") 
		row_count=$(echo "$rows" | sed '/^$/d' | wc -l)
		if [ -z "$rows" ] ; then 
			SCREEN_PROMPT="No messages for mobile: $ph\n\n1) Go back 2) Back to main menu"
			while true ; do
				showScreen
				read -p "Choice:" opt
				case "$opt" in
					1) continue 2;;
					2) break 2;;
				esac
			done
		fi
		if [ -t 0 ] ; then stty -echo -icanon time 0 min 0; fi
		for line in $rows ; do
			key="$(cat 2>/dev/null)"
			if echo "$key" | grep c ; then
				if [ -t 0 ] ; then stty $SAVE_TERM; fi
				IFS=$OIFS
				break 2
			fi
			SCREEN_PROMPT="Retrieving message chain for mobile: $ph\n\n${BOLD_YELLOW}Processing row $((i=i+1)) / $row_count${NTA}\n\nc) Cancel operation"
			showScreen
			msg_id=$(echo "$line" | cut -d'|' -f1)
			date=$(echo "$line" | cut -d'|' -f3)
			msg=$(echo "$line" | cut -d'|' -f4)
			if [ "$msg_id" = "OUTBOUND" ] ; then
				unsorted="$unsorted$(printf "O|%s|%s\n" "$date" "$msg")\n"
			else # inbound. a message id 
				if [ -z "$msg" ] ; then
					checkResponse "$msg_id"
					return_code=$?
					resp="$RETURN_VAL"
					if [ $return_code -eq 1 ] ; then
						SCREEN_PROMPT="${BOLD_RED}Server timeout${NTA} Press ENTER to return"
						showScreen
						read REPLY
						break 2
					elif [ $return_code -eq 2 ] ; then
						continue
					fi
					date=$(echo "$resp" | cut -d'|' -f2 | sed s/\s//g)
					date=$(date -d "$date" +"%s")
					msg=$(echo "$resp" | cut -d'|' -f3 | cut -c2-)
					sed -r -iOLD "s/${msg_id}.*/&\|$date\|$msg/" "$DATA_FILE"
				fi
				unsorted="$unsorted\n$(printf "I|%s|%s\n" "$date" "$msg")\n"
			fi
		done
		sorted=$(printf "$unsorted" | sort -t'|' -n -k2) # sort messages by time in ascending order
		i=0
		row_count=$(echo "$sorted" | wc -l)
		for line in $sorted ; do
			key="$(cat 2>/dev/null)"
			if echo "$key" | grep c ; then
				if [ -t 0 ] ; then stty $SAVE_TERM; fi
				IFS=$OIFS
				SCREEN_PROMPT="Message chain for mobile: $ph\n\nProcessed row $i / $row_count\n\n$(printf "%-11s | %-19s | %-s\n" "In/Outbound" "Date" "Message")\n$all_res\n${BOLD_RED}Operation cancelled.${NTA} Press ENTER to go to main menu"
				showScreen
				read REPLY
				break 2
			fi
			i=$((i + 1))
			date=$(echo "$line" | cut -d'|' -f2)
			date=$(date -d @$date +%Y-%m-%dT%H:%M:%S) # convert time field to human readable format
			dir=$(echo $line | cut -c1)
			msg=$(echo $line | cut -d'|' -f3)
			res=$(printf "%-11s | %s | %s\n" "$dir" "$date" "$msg")
			all_res="$all_res$res\n"
			SCREEN_PROMPT="Message chain for mobile: $ph\n\n${BOLD_YELLOW}Processed row $i / $row_count\t\tc) Cancel operation${NTA}\n\n$(printf "%-11s | %-19s | %-s\n" "In/Outbound" "Date" "Message")\n$all_res"
			showScreen
		done
		if [ -t 0 ] ; then stty $SAVE_TERM; fi
		SCREEN_PROMPT="Message chain for mobile: $ph\n\n$(printf "%-11s | %-19s | %-s\n" "In/Outbound" "Date" "Message")\n$all_res\n1) Check another mobile 2) Back to main menu"
		while true ; do
			showScreen
			read -p "Choice:" opt
			case "$opt" in
				1) ph=; continue 2;;
				2) break 2;;
			esac
		done
	done
	IFS=$OIFS
}

############
# Restore terminal settings and show warnings if script is force closed
# Globals:
# 		SAVE_TERM
# 		DATA_FILE
# Arguments:
# 		None
# Returns:
# 		None
############
cleanUp() {
	printf "\033c\r" # clears screen. compatible with VT100 terminals
	echo "Cleaning up before exit. Restore $DATA_FILE with ${DATA_FILE}OLD if needed" 
	stty $SAVE_TERM
	exit 1
}

###########
# Check whether authentication token is expired  
# Globals:
# 		TOKEN
# 		SCREEN_PROMPT
# 		TOKEN_EXPIRE
# 		APP_KEY
# 		APP_SECRET
# 		TOKEN_INTERVAL
# 		KEY_FILE
# Arguments:
# 		None
# Returns:
# 		1: On server timeout
###########
checkToken() {
	if [ $(($(date +%s) - $TOKEN_EXPIRE)) -gt 0 ] ; then # token expired
		TOKEN=$(curl --connect-timeout 5 -m 5 -s "https://api.telstra.com/v1/oauth/token?client_id=$APP_KEY&client_secret=$APP_SECRET&grant_type=client_credentials&scope=SMS")
		if [ $? -ne 0 ] ; then
			SCREEN_PROMPT="Server took too long to respond. Could not update auth token. Press ENTER to continue"
			showScreen
			read REPLY
			return 1
		fi
		TOKEN_INTERVAL=$(($(echo "$TOKEN" | grep -Po "expires_in\":\s*\"\K\d+") - 60)) 		
		TOKEN=$(echo $TOKEN | grep -Po "access_token\": \"\K\w+")
		TOKEN_EXPIRE=$(($(date +%s) + $TOKEN_INTERVAL))
		sed -i "4c $TOKEN_EXPIRE" "$KEY_FILE"
		sed -i "3c $TOKEN" "$KEY_FILE"
	fi	
}

if [ $# -ne 2 ] && [ $# -ne 4 ] ; then
	printf "Usage: $0 {api key file} {data file} [mobile "message"]

\tmobile - eg.0412345678
\tmessage - Message must be wrapped in double quotes.  If longer than 160 characters, message is truncated
\tdata file - stores message data. Can read from existing file or create a new one if it doesn't exist.
\tapi key file - If you don't have an app key/secret, sign up for a T.Dev account at https://dev.telstra.com/ and create a new app using the SMS API.  Put the app key on line 1 and app secret on line 2 of the api key file\n"
	exit 1
fi

# check key file exists and permissions
[ -e "$1" ] || { echo "Key file $1 not found"; exit 1; }
[ -r "$1" ] && [ -w "$1" ] || { echo "Key file $1 must be readable and writable. Check permissions"; exit 1; } 

KEY_FILE="$1"		
APP_KEY=$(sed -n 1p "$KEY_FILE")
APP_SECRET=$(sed -n 2p "$KEY_FILE")
TOKEN=$(sed -n 3p "$KEY_FILE")
TOKEN_EXPIRE=$(sed -n 4p "$KEY_FILE")

if [ -z "$TOKEN" ] ; then # no token found in key file
	TOKEN=$(curl --connect-timeout 5 -m 5 -s "https://api.telstra.com/v1/oauth/token?client_id=$APP_KEY&client_secret=$APP_SECRET&grant_type=client_credentials&scope=SMS")
	if [ $? -ne 0 ] ; then
		SCREEN_PROMPT="Server took too long to respond. Could not update auth token. Script will now quit. Press ENTER to continue."
		showScreen
		read REPLY
		exit
	fi
	TOKEN_INTERVAL=$(($(echo "$TOKEN" | grep -Po "expires_in\":\s*\"\K\d+") - 60))
	TOKEN=$(echo "$TOKEN" | grep -Po "access_token\": \"\K\w+")
	echo "$TOKEN" >> "$KEY_FILE"
	TOKEN_EXPIRE=$(($(date +%s) + $TOKEN_INTERVAL))
	echo "$TOKEN_EXPIRE" >> "$KEY_FILE"
fi

# check data file exists and permissions
if [ -e "$2" ] ; then
	[ -w "$2" ] && [ -r "$2" ] || { echo "Data file $2 be readable and writable. Check permissions"; exit 1; }
else
	touch "$2"
fi
DATA_FILE="$2" 	

# send text message from command line
if [ $# -eq 4 ] ; then		
	sendText "$3" "${4:0:160}"
	if [ $? -eq 0 ] ; then
		printf "Message sent. To check status/response, use message id: ${RETURN_VAL}\nIt has been added to file ${DATA_FILE}.\n"
		echo "$RETURN_VAL|$3" >> "$DATA_FILE"
		echo "OUTBOUND|$3|$(date +"%Y%m%d%H%M%S" | cut -c1-19)|$4" >> "$DATA_FILE"
		exit 0
	else
		echo "Message not sent. Server error $RETURN_VAL"
		exit 1
	fi
fi

trap cleanUp SIGINT SIGTERM
#trap showScreen WINCH
while true ; do
	RETURN_VAL=$(($TOKEN_EXPIRE - $(date +%s)))
	[ $RETURN_VAL -gt 0 ] && RETURN_VAL="${RETURN_VAL}s" || RETURN_VAL='On next operation'
	SCREEN_TITLE="Main Menu"
	SCREEN_PROMPT="Send up to 100 SMS free per day to any Australian mobile
Data file: [$DATA_FILE]
Token update ETA: [$RETURN_VAL]
\n1) Send text
2) Check status
3) Check response
4) Check all statuses
5) Check all responses
6) Check message chain
q) Quit"
	showScreen
	read -p "Choice:" CHOICE
	case $CHOICE in
		1)	optSendText;;
		2) optStatus;;
		3) optResponse;;
		4) optStatuses;;
		5) optResponses;;
		6) optMessageChain;;
		q)
			printf "\033c\r" # clears screen. compatible with VT100 terminals
			echo Bye 
			break
		;;
	esac
done
