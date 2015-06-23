# TelstraSmsApiBashScript 
---

<!-- MarkdownTOC -->

- [Intro](#intro)
- [Requirements](#requirements)
- [Before running the script](#before-running-the-script)
- [Running the script](#running-the-script)
- [Known issues](#known-issues)
- [Change log](#change-log)

<!-- /MarkdownTOC -->


## Intro 
[Telstra SMS API](https://dev.telstra.com/content/sms-api-0) currently lets you send text messages to any Australian mobile phone number [for free for the time being as it undergoes beta testing](https://dev.telstra.com/pricing).  100 text limit per day. 

This script enables you to send SMS, check delivery status and any replies received.

![Telstra SMS script menu](https://cloud.githubusercontent.com/assets/9711999/8271000/2d08f8bc-1843-11e5-9f88-c41268d04721.PNG)

## Requirements
* Linux system, bash 4+ & curl
* Tested working in Cygwin (bash 4.3.39(2)-release, curl 7.42.1)
* Tested working in Ubuntu (bash 4.3.11(1)-release, curl 7.35.0)

## Before running the script
To use this script, [register for a free T.Dev account](https://dev.telstra.com/).  

Once registered

1. goto **MyApps**
2. click on **Add a new app**
3. Select **SMS API**
4. Give your app any name and type in anything for the SMS callback URL (eg. your blog site).  When a person responds to your sms, Telstra sends a request to that URL to inform your app of the respondent's message.  This script doesn't use that functionality.
5. Once you get a consumer key and secret, create a new file located in the same dir as the script. On line 1 add the key. On line 2 add the secret.  
6. Run the script `./sms.sh <key file>`

## Running the script
### Non-interactive mode
The fastest way to send SMS is to run the script with command line args: `./sms.sh <key file> <data file> <mobile> "<message>"`.  
_Be careful sending a message via command line_
Be sure to wrap **double quotes around message** otherwise only the first word will be sent!  

If the message itself contains a double quote, you must replace it with \"

  ```Eg. "hi" becomes \"hi\"```

$ must be replaced with \$

```Eg. $2 becomes \$2```

If the message is longer than 160 characters, the message will be truncated. 

The above replacements are due to the way bash interprets command line args.  You can also wrap the message in single quotes but then single quotes within the message need to be replaced with `'\''`. These problems don't apply when sending a message interactively (described below).

The script will create a data file with the given name if it doesn't exist.  Otherwise, it will read and append data to an existing one.

### Interactive mode
The script can also be run interactively: `./sms.sh <key file> <data file>`.  This lets you:

1. send sms - with a message character count checker and confirm screen
2. check status - see if your message/s got delivered given a message id
3. check response/s - see the replies to your messages given a message id
4. check message chain - see all replies given a mobile number

![Telstra SMS script send text](https://cloud.githubusercontent.com/assets/9711999/8271004/37e1fb08-1843-11e5-9ae6-41da3af65cd5.PNG)

## Known issues
* In check message chain, inbound messages appear before corresponding outbound messages due to Telstra incorrectly handling timestamps.  [A fix is coming soon.](https://dev.telstra.com/content/timestamp-formats-inconsistent)

## Change log
* Updated readme and usage instructions - certain characters need replacement when sending message non-interactively
* Added character count in send message confirm screen
