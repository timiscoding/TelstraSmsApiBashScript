# TelstraSmsApiBashScript
# github.com/timiscoding

#!/bin/bash
DATA_FILE="msg_ids" # store message id and outbound sms data
TMP_FILE="temp.sms.sh.$$.$RANDOM"	# tmp file to store results for optMessageChain
NTA='\033[0m' # No text attributes
BOLD_RED='\033[31;1;40m'  
INV='\033[47;30m' # dark grey background, white text
BOLD='\033[7m'
BOLD_GREEN='\033[32;1;40m'
BOLD_YELLOW='\033[33;1;40m'
SCREEN_TITLE=		# top bar text
SCREEN_PROMPT=		# text to show user. eg menus and options
RETURN_VAL=			# return value for all functions
SAVE_TERM="$(stty -g)"	# save term settings 

############
#
# sendText - make Telstra API call to send a text message
# 
############
function sendText(){
	local phone=$1
	local msg=$(echo "$2" | sed 's/"/\\\"/g')		# double quotes need to be escaped for JSON 
	local resp=$(
		curl -s -H "Content-Type: application/json" \
		-H "Authorization: Bearer $TOKEN" \
		-d "{\"to\":\"$phone\", \"body\":\"$msg\"}" \
		"https://api.telstra.com/v1/sms/messages") 
	local server_status=$(echo "$resp" | grep -Po "status\":\s\K\d+")
	local server_msg=$(echo "$resp" | grep -Po "message\":\s\K[\w\s]+")
	local msg_id=$(echo "$resp" | grep -Po "messageId\":\"\K\w+")
	if [ -n "$msg_id" ] ; then
		RETURN_VAL="$msg_id"
		return 0
	else
		RETURN_VAL="${server_status} ${server_msg}"
		return 1
	fi
}

############
#
# checkStatus - make Telstra API call to get delivery status for a message
#
############
function checkStatus(){
	RETURN_VAL=
	local id=$1
	local resp=$(curl -sH "Authorization: Bearer $TOKEN" "https://api.telstra.com/v1/sms/messages/$id")
	local ph=$(echo "$resp" | grep -Po "to\":\"\K\d+" | sed s/^61/0/)
	local received=$(echo "$resp" | grep -Po "receivedTimestamp\":\"\K[\w:-]+")
	local sent=$(echo "$resp" | grep -Po "sentTimestamp\":\"\K[\w:-]+")
	local status=$(echo "$resp" | grep -Po "status\":\"\K\w+")
	if [ -n "$status" ] ; then
		RETURN_VAL="$(printf "%10s | %19s | %19s | %s\n" "$ph" "$received" "$sent" "$status")"
	fi
}

###########
#
# checkResponse - make Telstra API call to get reply for a message
#
###########
function checkResponse(){
	RETURN_VAL=
	local id=$1
	local resp=$(curl -sH "Authorization: Bearer $TOKEN" "https://api.telstra.com/v1/sms/messages/$id/response")
	local ph=$(echo "$resp" | grep -Po "from\":\"\K\d+" | sed s/^61/0/)
	local date=$(echo "$resp" | grep -Po "Timestamp\":\"\K[\w:-]+")
	local content=$(echo "$resp" | grep -Po "content\":\"\K.+(?=\")")
	if [ -n "$date" ] ; then
		RETURN_VAL="$(printf "%10s | %19s | %s\n" "$ph" "$date" "$content")"
	fi	
}

##########
#
# showScreen - display top bar, menu, options
#
##########
function showScreen(){
	local ROWS=$(stty size | cut -d' ' -f1)
	local COLS=$(stty size | cut -d' ' -f2)
	local name="Telstra Sms Api Bash script"
	printf "\033c\r" # clears screen. compatible with VT100 terminals
	printf "${INV}%-*s%s\n${NTA}" $(($COLS - ${#name})) "$SCREEN_TITLE" "$name" # top bar
	printf "%0.s=" $(seq 1 $COLS) # print upper border
	echo -e '\n'
	echo -e "$SCREEN_PROMPT" | sed 's/^/ /'
	echo
	printf "%0.s=" $(seq 1 $COLS) # print upper border
}

###########
#
# getInput - get user input for phone/message/message id
#
###########
function getInput(){
	local type=$1
	local text=$2		# initial text 
	local prompt=$3	# text to show before waiting for input
	case $type in
		PH)
			read -p "$prompt" -i "$text" -e RETURN_VAL
		;;
		MSG)
			while true ; do
				echo "$prompt"
				read -i "$text" -e RETURN_VAL
				if [ ${#RETURN_VAL} -gt 160 ] ; then
					text="$RETURN_VAL"
					showScreen
					echo -e "${BOLD_RED}Message has ${#RETURN_VAL} characters${NTA}"
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
#
# optSendText - menu option for sending text message
#
##########
function optSendText(){
	SCREEN_TITLE="Send Text"
	local s1="1. Enter mobile"
	local s2="2. Enter message"
	local s3="3. Confirmation screen"
	SCREEN_PROMPT="${BOLD}${s1}${NTA}\n${s2}\n${s3}\n\n b) Back to main menu"
	local ph
	local msg
	local res	# message ID result
	local exitCode
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
				exitCode=$?
				res="$RETURN_VAL"
				if [ $exitCode -ne 0 ] ; then
					SCREEN_PROMPT="${BOLD_RED}Server error $res${NTA}\n\nPress ENTER to return"
					showScreen
					read
					continue
				fi
				echo "$res|$ph" >> "$DATA_FILE"
				echo "OUTBOUND|$ph|$(date +"%Y%m%d%H%M%S" | cut -c1-19)|$msg" >> "$DATA_FILE"
				SCREEN_PROMPT="${BOLD_GREEN}Message sent.${NTA} To check status/response, use message id:\n\n\t${res}\n\nIt has been added to file ${DATA_FILE}. Press ENTER to return"
				showScreen
				read
				break
			;;
			4)
				break
			;;
		esac
	done
}

###########
#
# optStatus - menu option for checking message delivery status
#
###########
function optStatus(){
	local msg_id
	local res		# delivery status result
	local opt		# key pressed option
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
		res="$RETURN_VAL"
		if [ -n "$res" ] ; then
			SCREEN_PROMPT="Delivery status for message id: $msg_id\n\n$(printf "%-10s | %-19s | %-19s | %s" "Mobile" "Received" "Sent" "Status")\n$res\n\n1) Go back\t2) Back to main menu"
		else
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
#
# optResponse - menu option for checking a reply to a message
#
############
function optResponse(){
	local msg_id
	local res	# reply result
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
		checkResponse $msg_id
		res="$RETURN_VAL"
		if [ -n "$res" ] ; then
			SCREEN_PROMPT="Response status for message id: $msg_id\n\n$(printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message")\n$res\n\n1)Go back\t2) Back to main menu"
		else
			SCREEN_PROMPT="Response status for message id: $msg_id\n\n${BOLD_RED}No results. Please check message id.${NTA}\n\n1)Go back\t2) Back to main menu"				 
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
#
# optStatuses - menu option to check delivery status for all message ids 
# 					 stored in file DATA_FILE
#
#############
function optStatuses(){
	local msg_ids
	local msg_id_count
	local res		# status for a single message
	local all_res	# statuses for all messages
	local i=0		# progress counter for getting statuses
	local res_count=0		# number of results found
	SCREEN_TITLE="Check All Statuses"
	msg_ids=$(cat "$DATA_FILE" | cut -d'|' -f1 | grep -v OUTBOUND)
	msg_id_count=$(echo "$msg_ids" | sed '/^$/d' | wc -l)
	if [ -t 0 ] ; then stty -echo -icanon time 0 min 0; fi		# set non-blocking user input
	for id in $msg_ids ; do
		key="$(cat 2>/dev/null)"	# read for any user input during data collection. redirect to /dev/null is to stop 'resource temporarily unavail' error in cygwin
		SCREEN_PROMPT="Checking all statuses in file ${DATA_FILE}\n\n${BOLD_YELLOW}Processing message ID $((++i)) / $msg_id_count${NTA}\n\nc) Cancel operation"
		showScreen
		checkStatus $id
		res="$RETURN_VAL"
		[ -n "$res" ] && { res_count=$((res_count + 1)); all_res="$all_res$res\n"; }
		if [[ "$key" =~ c ]] ; then		# user wants to cancel operation
			if [ -t 0 ] ; then stty $SAVE_TERM; fi
			return
		fi
	done 
	if [ -t 0 ] ; then stty $SAVE_TERM; fi
	if [ $res_count -gt 0 ] ; then
		SCREEN_PROMPT="Found $res_count results from $msg_id_count message IDs:\n\n$(printf "%-10s | %-19s | %-19s | %s\n" "Mobile" "Received" "Sent" "Status")\n$all_res\nPress ENTER to return"
	else
		SCREEN_PROMPT="Found 0 results from $msg_id_count message IDs.\n\nPress ENTER to return"
	fi
	showScreen
	read				 
}

#############
#
# optResponses - menu option for checking replies to all message ids 
# 					  in file DATA_FILE
#
#############
function optResponses(){
	local msg_ids
	local msg_id_count
	local res		# reply for a single message
	local all_res	# replies for all messages
	local i=0		# progress counter when getting all replies
	local res_count=0		# number of replies found
	SCREEN_TITLE="Check All Responses"
	msg_ids=$(cat "$DATA_FILE" | cut -d'|' -f1 | grep -v OUTBOUND)
	msg_id_count=$(echo "$msg_ids" | sed '/^$/d' | wc -l)
	if [ -t 0 ] ; then stty -echo -icanon time 0 min 0; fi
	for id in $msg_ids ; do
		key="$(cat 2>/dev/null)"
		SCREEN_PROMPT="Checking all responses in file ${DATA_FILE}\n\n${BOLD_YELLOW}Processing message ID $((++i)) / $msg_id_count${NTA}\n\nc) Cancel operation"
		showScreen
		checkResponse $id	
		res="$RETURN_VAL"
		[ -n "$res" ] && { res_count=$((res_count + 1)); all_res="$all_res$res\n"; }
		if [[ "$key" =~ c ]] ; then
			if [ -t 0 ] ; then stty $SAVE_TERM; fi
			return
		fi
	done
	if [ -t 0 ] ; then stty $SAVE_TERM; fi
	if [ $res_count -gt 0 ] ; then
		SCREEN_PROMPT="Found $res_count results from $msg_id_count message IDs:\n\n$(printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message")\n$all_res\nPress ENTER to return"
	else
		SCREEN_PROMPT="Found 0 replies from $msg_id_count message IDs.\n\nPress ENTER to return"
	fi
	showScreen
	read				 
}

#############
#
# optMessageChain - menu option for returning all inbound/outbound messages in 
#						  chronological order for a given mobile
#
#############
function optMessageChain(){
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
	OIFS=$IFS
	IFS=$'\n'
	while true ; do
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
			SCREEN_PROMPT="Retrieving message chain for mobile: $ph\n\n${BOLD_YELLOW}Processing row $((++i)) / $row_count${NTA}\n\nc) Cancel operation"
			showScreen
			msg_id=$(echo "$line" | cut -d'|' -f1)
			date=$(echo "$line" | cut -d'|' -f3)
			msg=$(echo "$line" | cut -d'|' -f4)
			if [ "$msg_id" = "OUTBOUND" ] ; then
				printf "O|%s|%s\n" "$date" "$msg" >> "$TMP_FILE"
			else # inbound. a message id 
				if [ -z "$msg" ] ; then
					checkResponse "$msg_id"
					resp="$RETURN_VAL"
					[ -z "$resp" ] && continue
					date=$(echo "$resp" | cut -d'|' -f2 | sed s/\s//g)
					date=$(date -d "$date" +"%Y%m%d%H%M%S")
					msg=$(echo "$resp" | cut -d'|' -f3 | cut -c2-)
					sed -r -iOLD "s/${msg_id}.*/&\|$date\|$msg/" "$DATA_FILE"
				fi
				printf "I|%s|%s\n" "$date" "$msg" >> "$TMP_FILE"
			fi
			if [[ "$key" =~ c ]] ; then
				if [ -t 0 ] ; then stty $SAVE_TERM; fi
				IFS=$OIFS
				break 2
			fi
		done
		sorted=$(cat "$TMP_FILE" | sort -t'|' -n -k2) # sort messages by time in ascending order
		[ -e "$TMP_FILE" ] && rm "$TMP_FILE"
		i=0
		row_count=$(echo "$sorted" | wc -l)
		for line in $sorted ; do
			key="$(cat 2>/dev/null)"
			SCREEN_PROMPT="Generating results...\n\n${BOLD_YELLOW}Processing row $((++i)) / $row_count${NTA}\n\nc) Cancel operation"
			showScreen
			date=$(echo "$line" | cut -d'|' -f2 | sed -r "s/(.{4})(.{2})(.{2})(.{2})(.{2})(.{2})/\1-\2-\3 \4:\5:\6/") # convert time field to human readable format
			dir=$(echo $line | cut -c1)
			msg=$(echo $line | cut -d'|' -f3)
			res=$(printf "%-11s | %s | %s\n" "$dir" "$date" "$msg")
			all_res="$all_res$res\n"
			if [[ "$key" =~ c ]] ; then
				if [ -t 0 ] ; then stty $SAVE_TERM; fi
				IFS=$OIFS
				break 2
			fi
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
#
# cleanUp - do some maintenence if script is force closed
#
############
function cleanUp() {
	printf "\033c\r" # clears screen. compatible with VT100 terminals
	echo "Cleaning up before exit. Restore $DATA_FILE with ${DATA_FILE}OLD if needed" 
	[ -e "$TMP_FILE" ] && rm "$TMP_FILE"
	stty $SAVE_TERM
	exit 1
}

if [ $# -ne 2 -a $# -ne 4 ] ; then
	echo -e "Usage: $0 {api key file} {data file} [mobile "message"]

\tmobile - eg.0412345678
\tmessage - Message must be wrapped in double quotes.  If longer than 160 characters, message is truncated
\tdata file - stores message data. Can read from existing file or create a new one if it doesn't exist.
\tapi key file - If you don't have an app key/secret, sign up for a T.Dev account at https://dev.telstra.com/ and create a new app using the SMS API.  Put the app key on line 1 and app secret on line 2 of the api key file"
	exit 1
fi

# check for valid key and generate auth token
[ -e "$1" ] || { echo "Key file $1 not found"; exit 1; }
[ -r "$1" ] || { echo "Key file $1 unreadable. Check permissions"; exit 1; } 
APP_KEY=$(cat "$1" | head -n1)
APP_SECRET=$(cat "$1" | tail -n1)
TOKEN=$(curl -s "https://api.telstra.com/v1/oauth/token?client_id=$APP_KEY&client_secret=$APP_SECRET&grant_type=client_credentials&scope=SMS" | grep -Po "access_token\": \"\K\w+")

# check data file
if [ -e "$2" ] ; then
	[ -w "$2" ] || { echo "Data file $2 not writable. Check permissions"; exit 1; }
	[ -r "$2" ] || { echo "Data file $2 not readable. Check permissions"; exit 1; }
else
	touch "$2"
fi
DATA_FILE="$2"			

# send text message from command line
if [ $# -eq 4 ] ; then		
	sendText "$3" "${4:0:160}"
	if [ $? -eq 0 ] ; then
		echo -e "Message sent. To check status/response, use message id: ${RETURN_VAL}\nIt has been added to file ${DATA_FILE}."
		echo "$RETURN_VAL|$3" >> "$DATA_FILE"
		echo "OUTBOUND|$3|$(date +"%Y%m%d%H%M%S" | cut -c1-19)|$4" >> "$DATA_FILE"
		exit 0
	else
		echo "Message not sent. Server error $RETURN_VAL"
		exit 1
	fi
fi

trap clean_up SIGINT SIGTERM
while true ; do
	SCREEN_TITLE="Main Menu"
	SCREEN_PROMPT="Send up to 100 SMS free per day to any Australian mobile
Data file: [$DATA_FILE]
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
