#!/bin/bash
if [ $# -ne 1 ] ; then
   echo -e "Usage: $0 {api key file}\nIf you don't have an app key/secret, sign up for a T.Dev account at https://dev.telstra.com/ and create a new app using the SMS API.  Put the app key on line 1 and app secret on line 2 of the api key file"
   exit 1
fi
if [ $# -eq 1 ] ; then
   if [ -e $1 ] ; then
      APP_KEY=$(cat $1 | head -n1)
      APP_SECRET=$(cat $1 | tail -n1)
   else
      echo "api key file not found."
      exit 1
   fi
fi

TOKEN=$(curl -s "https://api.telstra.com/v1/oauth/token?client_id=$APP_KEY&client_secret=$APP_SECRET&grant_type=client_credentials&scope=SMS" | grep -Po "access_token\": \"\K\w+")

function sendText(){
   PHONE=$1
   MSG=$2

   MSG_ID=$(
       curl -s -H "Content-Type: application/json" \
       -H "Authorization: Bearer $TOKEN" \
       -d "{\"to\":\"$PHONE\", \"body\":\"$MSG\"}" \
       "https://api.telstra.com/v1/sms/messages" | grep -Po "messageId\":\"\K\w+")
}

function checkStatus(){
   local ID=$1
   curl -H "Authorization: Bearer $TOKEN" "https://api.telstra.com/v1/sms/messages/$ID"
   echo
}

function checkResponse(){
   local ID=$1
   curl -H "Authorization: Bearer $TOKEN" "https://api.telstra.com/v1/sms/messages/$ID/response"
   echo
}

function clrScreen(){
   printf "\033c" # clears screen. compatible with VT100 terminals
}

while true ; do
   clrScreen
   echo -e "
========================================================
| Telstra SMS script - send up to 100 SMS free per day |
| 1. Send text					       |
| 2. Check status				       |
| 3. Check response				       |
| 4. Check all statuses				       |
| 5. Check all responses			       |
| q. Quit					       |
========================================================
Choice: \c"					    
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
         STATUS1="Enter text message (" 
         STATUS2=" / 160 char limit used) "
         echo "${STATUS1}0$STATUS2"
         while read -sn1 ch ; do
            clrScreen
            if [ "$ch" == $'\177' ] ; then  # char is backspace 
   	       if [ "$MSG_LEN" -gt 0 ] ; then
                  MSG="${MSG%?}"
                  echo "$STATUS1$((--MSG_LEN))$STATUS2"
                  echo -ne "$MSG \r"
               else
   	          echo "$STATUS1$MSG_LEN$STATUS2"   
               fi
            elif [ "$ch" == $'\0' ] ; then
               if [ $MSG_LEN -eq 0 ] ; then
   	       ERROR='ERROR: Message empty. Please type something'
                  echo "$STATUS1$MSG_LEN${STATUS2}$ERROR"
                  echo -ne "$MSG \r"
   	    else
   	       break  
   	    fi
   	 else
               if [ $MSG_LEN -ge 160 ] ; then
                  ERROR='ERROR: Max message size reached'
                  echo "$STATUS1$MSG_LEN${STATUS2}$ERROR"
                  echo -ne "$MSG \r"
      	    else
                  MSG=$MSG$ch
      	       echo "$STATUS1$((++MSG_LEN))$STATUS2"
                  echo -ne "$MSG \r"
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
      	    echo "To check status/response, use message id: ${MSG_ID} It has been added to file msg_ids"
      	    echo $MSG_ID >> msg_ids
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
         checkStatus $id
         echo "Press ENTER to return"
         read             
      ;;
      3)
         clrScreen
         echo -ne "check response. Enter message id:\c"
         read id
         checkResponse $id
         echo "Press ENTER to return"
         read             
      ;;
      4)
         clrScreen
         echo "Checking all statuses"
         cat msg_ids | while read id ; do
             checkStatus $id
         done
         echo "Press ENTER to return"
         read             
      ;;
      5)
         clrScreen
         echo -ne "Check response\nEnter message id:\c"
         cat msg_ids | while read id ; do
            checkResponse $id
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

