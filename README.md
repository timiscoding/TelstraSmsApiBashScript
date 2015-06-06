# TelstraSmsApiBashScript
[Telstra SMS API](https://dev.telstra.com/content/sms-api-0) currently lets you send text messages to any Australian mobile phone number [for free for the time being](https://dev.telstra.com/pricing).  100 text limit per day. 

To use this script, all you have to do is [register for a free T.Dev account](https://dev.telstra.com/).  

Once registered

1. goto MyApps
2. click on Add a new app
3. Select SMS API
4. Give your app any name and type in anything for the SMS callback URL (eg. your blog site).  When a person responds to your sms, Telstra sends a request to that URL to inform your app of the respondent's message.  This script doesn't use that functionality.
5. Once you get a consumer key and secret, create a new file located in the same dir as the script. On line 1 add the key. On line 2 add the secret.  
6. Run the script ./sms.sh appkeyfile

A few caveats
* Requires a Linux system, bash & curl to be installed
