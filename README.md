# TelstraSmsApiBashScript 
---

<!-- MarkdownTOC -->

- [Intro](#intro)
- [Requirements](#requirements)
- [Before running the script](#before-running-the-script)
- [Running the script](#running-the-script)
- [Limitations](#limitations)

<!-- /MarkdownTOC -->


## Intro 
[Telstra SMS API](https://dev.telstra.com/content/sms-api-0) currently lets you send text messages to any Australian mobile phone number [for free for the time being as it undergoes beta testing](https://dev.telstra.com/pricing).  100 text limit per day. 

This script enables you to send SMS and check delivery status and any replies received.

## Requirements
* Linux system, bash & curl

## Before running the script
To use this script, [register for a free T.Dev account](https://dev.telstra.com/).  

Once registered

1. goto **MyApps**
2. click on **Add a new app**
3. Select **SMS API**
4. Give your app any name and type in anything for the SMS callback URL (eg. your blog site).  When a person responds to your sms, Telstra sends a request to that URL to inform your app of the respondent's message.  This script doesn't use that functionality.
5. Once you get a consumer key and secret, create a new file located in the same dir as the script. On line 1 add the key. On line 2 add the secret.  
6. Run the script `./sms.sh keyfile`

## Running the script
The fastest way to send SMS is to run the script with command line args: `./sms.sh <key file> <mobile> "<message>"`.  If the message is longer than 160 characters, the message will be truncated.

The script can also be run interactively: `./sms.sh <key file>`.  This lets you:

1. send sms - with a character counter and confirm screen
2. check status - see if your message/s got delivered given a message id
3. check response/s - see the replies to your messages given a message id
4. check message chain - see all replies given a mobile number

## Limitations

* When typing a message in interactive mode, use backspace to delete.  Currently, you can't move the cursor or use delete to edit.