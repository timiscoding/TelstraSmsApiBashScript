#!/bin/bash
MSG_ID_FILE="msg_ids" # store message id and outbound sms data
function sendText(){
	PHONE=$1
	MSG=$(echo "$2" | sed 's/"/\\\"/g')
	local RESP=$(
		curl -s -H "Content-Type: application/json" \
		-H "Authorization: Bearer $TOKEN" \
		-d "{\"to\":\"$PHONE\", \"body\":\"$MSG\"}" \
		"https://api.telstra.com/v1/sms/messages") 
	SERVER_STATUS=$(echo "$RESP" | grep -Po "status\":\s\K\d+")
	SERVER_MSG=$(echo "$RESP" | grep -Po "message\":\s\K[\w\s]+")
	MSG_ID=$(echo "$RESP" | grep -Po "messageId\":\"\K\w+")
}

function checkStatus(){
	local ID=$1
	local RESP=$(curl -sH "Authorization: Bearer $TOKEN" "https://api.telstra.com/v1/sms/messages/$ID")
	local PH=$(echo "$RESP" | grep -Po "to\":\"\K\d+" | sed s/^61/0/)
	local RECEIVED=$(echo "$RESP" | grep -Po "receivedTimestamp\":\"\K[\w:-]+")
	local SENT=$(echo "$RESP" | grep -Po "sentTimestamp\":\"\K[\w:-]+")
	local STATUS=$(echo "$RESP" | grep -Po "status\":\"\K\w+")
	if [ -n "$STATUS" ] ; then
		printf "%s | %s | %s | %s\n" "$PH" "$RECEIVED" "$SENT" "$STATUS"
	fi
}

function checkResponse(){
	local ID=$1
	local RESP=$(curl -sH "Authorization: Bearer $TOKEN" "https://api.telstra.com/v1/sms/messages/$ID/response")
	local PH=$(echo "$RESP" | grep -Po "from\":\"\K\d+" | sed s/^61/0/)
	local DATE=$(echo "$RESP" | grep -Po "Timestamp\":\"\K[\w:-]+")
	local CONTENT=$(echo "$RESP" | grep -Po "content\":\"\K.+(?=\")")
	if [ -n "$DATE" ] ; then
		printf "%s | %s | %s\n" "$PH" "$DATE" "$CONTENT"
	fi	
}

function clrScreen(){
	printf "\033c" # clears screen. compatible with VT100 terminals
}

if [ $# -ne 1 -a $# -ne 3 ] ; then
	echo -e "Usage: $0 {api key file} [mobile "message"]\n\tmobile - eg.0412345678\n\tmessage - Message must be wrapped in double quotes.  If longer than 160 characters, message is truncated\nIf you don't have an app key/secret, sign up for a T.Dev account at https://dev.telstra.com/ and create a new app using the SMS API.  Put the app key on line 1 and app secret on line 2 of the api key file"
	exit 1
fi
if [ -e $1 ] ; then
	APP_KEY=$(cat $1 | head -n1)
	APP_SECRET=$(cat $1 | tail -n1)
	TOKEN=$(curl -s "https://api.telstra.com/v1/oauth/token?client_id=$APP_KEY&client_secret=$APP_SECRET&grant_type=client_credentials&scope=SMS" | grep -Po "access_token\": \"\K\w+")
else
	echo "api key file not found."
	exit 1
fi
if [ $# -eq 3 ] ; then
	sendText "$2" "${3:0:160}"
	echo -e "Message sent. To check status/response, use message id: ${MSG_ID}\nIt has been added to file ${MSG_ID_FILE}."
	echo "$MSG_ID|$2" >> "$MSG_ID_FILE"
	echo "OUTBOUND|$2|$(date +"%Y%m%d%H%M%S" | cut -c1-19)|$3" >> "$MSG_ID_FILE"
	exit 0
fi

while true ; do
	clrScreen
	M0= # for padding above M1 and below M7
	M1='Telstra SMS script - send up to 100 SMS free per day'
	M2='1. Send text'
	M3='2. Check status'
	M4='3. Check response'
	M5='4. Check all statuses'
	M6='5. Check all responses'
	M7='6. Check message chain'
	M8='q. Quit'
	printf "%0.s=" {1..56} # print upper border
	echo
	for item in "$M0" "$M1" "$M2" "$M3" "$M4" "$M5" "$M6" "$M7" "$M8" "$M0" ; do
		printf "| %-52s |\n" "$item" # longest string is 52 characters wide
	done
	printf "%0.s=" {1..56}
	echo -en "\nChoice:\c"
	read CHOICE
	case $CHOICE in
		1)
			clrScreen
			echo -ne "Send text\nEnter phone number:\c"
			read PH
	 		clrScreen
			OIFS=$IFS
			IFS='
'
			MSG_LEN=0 # message char count
         MSG=
			STATUS1="Enter text message (" 
			STATUS2=" / 160 char limit used) "
			echo "${STATUS1}0$STATUS2"
			while read -sn1 ch ; do
				clrScreen
				if [ "$ch" == $'\177' -o "$ch" == $'\010' ] ; then  # char is delete or backspace 
					if [ "$MSG_LEN" -gt 0 ] ; then
						MSG="${MSG%?}"
						echo "$STATUS1$((--MSG_LEN))${STATUS2}"
						echo -ne "$MSG"
					else
						echo "$STATUS1$MSG_LEN$STATUS2"	
					fi
				elif [ "$ch" == $'\0' ] ; then
					if [ $MSG_LEN -eq 0 ] ; then
						ERROR='ERROR: Message empty. Please type something'
						echo "$STATUS1$MSG_LEN${STATUS2}$ERROR"
						echo -ne "$MSG"
					else
						break  
					fi
				else
					if [ $MSG_LEN -ge 160 ] ; then
						ERROR='ERROR: Max message size reached'
						echo "$STATUS1$MSG_LEN${STATUS2}$ERROR"
						echo -ne "$MSG"
					else
						MSG=$MSG$ch
						echo "$STATUS1$((++MSG_LEN))${STATUS2}"
						echo -ne "$MSG"
					fi
				fi
			done
			IFS=$OIFS
			while true ; do
				clrScreen
				echo -en "Confirmation before sending text\nMobile: $PH\nMessage: $MSG\nChoose:\n\t1) send text\n\t2) back to main menu\n"
				read choice
				case $choice in
					1)
						echo sending text
						sendText "$PH" "$MSG"
						if [ -z "$MSG_ID" ] ; then
							echo -e "Server error $SERVER_STATUS: $SERVER_MSG\nPress ENTER to return"
							read
							continue 2
						fi
						echo "$MSG_ID|$PH" >> "$MSG_ID_FILE"
						echo "OUTBOUND|$PH|$(date +"%Y%m%d%H%M%S" | cut -c1-19)|$MSG" >> "$MSG_ID_FILE"
						echo -e "Message sent. To check status/response, use message id: ${MSG_ID}\nIt has been added to file ${MSG_ID_FILE}.\nPress ENTER to return"
						read
						break
					;;
					2)
						echo back to main menu
						break
					;;
				esac
			done
		;;
		2)
			clrScreen
			echo -ne "Check status\nEnter message id:\c"
			read id
			printf "%-10s | %-19s | %-19s | %s\n" "Mobile" "Received" "Sent" "Status"
			checkStatus $id
			echo "Press ENTER to return"
			read				 
		;;
		3)
			clrScreen
			echo -ne "check response. Enter message id:\c"
			read id
			printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message"
			checkResponse $id
			echo "Press ENTER to return"
			read				 
		;;
		4)
			clrScreen
			echo "Checking all statuses"
			printf "%-10s | %-19s | %-19s | %s\n" "Mobile" "Received" "Sent" "Status"
			OIFS=$IFS
			IFS="|"
			cat "$MSG_ID_FILE" | while read id ; do
				checkStatus $id
			done
			IFS=$OIFS
			echo "Press ENTER to return"
			read				 
		;;
		5)
			clrScreen
			echo "Checking all responses"
			OIFS=$IFS
			IFS="|"
			printf "%-10s | %-19s | %-s\n" "Mobile" "Date" "Message"
			cat "$MSG_ID_FILE" | while read id ; do
				checkResponse $id
			done
			IFS=$OIFS
			echo "Press ENTER to return"
			read				 
		;;
		6) 
			clrScreen
			echo -en "Checking message chain. Enter mobile:\c"
			read CHAIN_MOBILE
			ROWS=$(cat "$MSG_ID_FILE" | grep $CHAIN_MOBILE) 
			[ -z "$ROWS" ] && { echo "No messages for this number. Press ENTER to return"; read; continue; }
			printf "%-11s | %-19s | %-s\n" "In/Outbound" "Date" "Message"
			echo "$ROWS" | while read line ; do 
				ID=$(echo $line | cut -d'|' -f1)
				DATE=$(echo "$line" | cut -d'|' -f3)
				MSG=$(echo "$line" | cut -d'|' -f4)
				if [ "$ID" = "OUTBOUND" ] ; then
					printf "O|%s|%s\n" "$DATE" "$MSG" >> TMP$$
				else # inbound. ie. ID is a msg_id 
					if [ -z "$MSG" ] ; then
						RESP=$(checkResponse "$ID")
						[ -z "$RESP" ] && continue
						DATE=$(echo "$RESP" | cut -d'|' -f2 | sed s/\s//g)
						DATE=$(date -d "$DATE" +"%Y%m%d%H%M%S")
						MSG=$(echo "$RESP" | cut -d'|' -f3 | cut -c2-)
						sed -r -iOLD "s/$ID.*/&\|$DATE\|$MSG/" "$MSG_ID_FILE"
					fi
					printf "I|%s|%s\n" "$DATE" "$MSG" >> TMP$$
				fi
			done
			SORTED=$(cat TMP$$ | sort -t'|' -n -k2)
			[ -e TMP$$ ] && rm TMP$$
			echo "$SORTED" | while read line ; do
				DATE=$(echo "$line" | cut -d'|' -f2 | sed -r "s/(.{4})(.{2})(.{2})(.{2})(.{2})(.{2})/\1-\2-\3 \4:\5:\6/")
				DIR=$(echo $line | cut -c1)
				MSG=$(echo $line | cut -d'|' -f3)
				printf "%-11s | %s | %s\n" "$DIR" "$DATE" "$MSG"
			done
			echo "Press ENTER to return"
			read
		;;
		q)
			clrScreen
			echo Bye 
			break
		;;
	esac
done
