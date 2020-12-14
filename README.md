# unifiZabbix

This projet contains a collection of Templates to monitor Unifi and other UBNT devices with Zabbix: APs, Switches, Routers (USG and UDMP), AirMax devices, and NVRs

I am currently running those on the current versions of the base software as of Dec 2020: Zabbix 5.2, a mix of Unifi 4.x and 5.x APs and switches, AirMax 8.7.1, UDMP 1.8.3, controller 6.0.41


# Setup



## Install jq on your Zabbix server

You need to install jq on your system: https://stedolan.github.io/jq/

On Raspbian, this can be done with:

> apt-get install jq

## Install mca-dump-short script as a Zabbix external script

You need to install mca-dump-short.sh in Zabbix's external script directory

Please confirm where that directory is from the variable ExternalScripts in your zabbix server conf at /etc/zabbix/zabbix_server.conf.  On my system this is set to:

> ExternalScripts=/usr/lib/zabbix/externalscripts

After cp-ing the script to that directory, make sure you have the permissions necessary for zabbix to execute this script:

> chown zabbix:zabbix /usr/lib/zabbix/externalscripts /usr/lib/zabbix/externalscripts/mca-dump-short.sh
> chmod a+x /usr/lib/zabbix/externalscripts /usr/lib/zabbix/externalscripts/mca-dump-short.sh


## Import the Unifi templates into Zabbix

Import unifyTemplates.xml into Zabbix, from Configuration > Templates > Import

You should now have the following templates available, and it should be pretty self explanatory what type of device you need to link them to in Zabbix.

	Unifi AP
	Unifi Switch
	Unifi Router
	Unifi USG
	Unifi UDMP
	UBNT AirMax
	Unifi WiFi Site
	Unifi Protect Cloud Key
	Unifi Protect NVR4


You will need to assign the templates with the matching type to hosts with the proper IP/fqdn that you have created in Zabbix.

Unifi Wifi Site is a bit special and meant to aggregate WiFi traffic across your wifi networks for a Unifi site.  Just assign it to one of the APs that can see all the networks in question and assign the {$UNIFI_AP_GROUP} macro for that host to the name of a zabbix host group that contains all the APs for that site.

## Setup SSH from your Zabbix server to your Unifi devices via public/private keypair

These templates use public key SSH to access APs, Switches, Routers, AirMax stations and retrieve data directly, using the mca-dump or mca-status command line utility.  Your zabbix server (or your proxies if you use those) will need public key SSH access to all the unifi devices they are monitoring:

1/ You should generate a new key pair for this.  Zabbix is finicky and this is the specific way I needed to run the generation get a workable keypair (no passphrase, pem format). From your Zabbix server, run:

> ssh-keygen -P "" -t rsa  -m pem -f zb_id_rsa

put that keypair somewhere on your zabbix server (I put it in ~/.ssh/zabbix/)

You will need to specifically enable SSH access on the unifi devices.  There is one setting in the Unifi controller UI for devices at large in Settings > Site and one for the UDMP in the UDMP advanced settings which is separate.  The controller has handy UI to install your public key on all the devices, you will need to do it by hand on UDMPs and AirMax devices.  *ssh-copy-id* helps there, esp. on the UDMP since those will embarrasingly wipe all your keys at every firmware update and reboot (seriously UBNT).

Permissions can get in the way so check that your zabbix server can actually get the SSH access with:

> sudo -u zabbix ssh -i my-key-pair yourUserName@oneOfYouUnifiDevicesIP
  
If you are set up correctly that should get you in without asking for a password

You can also check that the script used to retrieve data is working correctly for a given device with:

> sudo -u zabbix /usr/lib/zabbix/externalscripts/mca-dump-short.sh -d <theDeviceIP> -u <yourUnifiUserName> -i <fullPathToYourPrivateKey> -t <UDMP|AP|SWITCH|CK>

You should get a JSON document in return.


2/ You then need to point Zabbix to those keys.  In your Zabbix conf file (/etc/zabbix/zabbix_server.conf typically) add:

> SSHKeyLocation=/the/path/to/your/keys


## Macros

In Zabbix, in Administration > General > Macros, you will need to set a value for __*all*__ the following macros:

### {$UNIFI_USER}
The username that will let the zabbix server (or proxy) log in to your unifi devices via SSH

### {$UNIFI_PRIV_KEY_PATH}
The full path private key filename to be able to SSH into your Unifi devices.  Please set this to the same value as SSHKeyLocation from your zabbix conf file.

### {$UNIFI_CHECK_FREQUENCY}
I have this set to '1m'

### {$UNIFI_ALERT_TEMP}
The temperature in Celsius above which to alert.  I have set this to '90'.

### {$UNIFI_ALERT_PERIOD}
The period after which to alert for most checks. I have this set to '10m'.

### {$UNIFI_SMOOTHING_COUNT}
I have this set to '#5'

### {$UNIFI_SMOOTHING_PERIOD}
I have this set to '10m'

Those last two are used to create moving averages that make graphs far easier to read.




# SUCCESS!

If you got this far, congratulations the install is complete!  Now for the funner part:


# Graphs

If everything is working you should be able to see data flowing in the Monitoring > Latest Data section of Zabbix.  Time to set up some graphs..  Unfortunately Zabbix doesn't to have a good way to share graphs as it does for templates, so here is a quick rundown of what I have setup..:


## Wan Download
![Wan Download](/images/wanDownload.png)

## Wan Upload
![Wan Upload](/images/wanUpload.png)

Observe the tight correlation between upload bandwidt and latency.. Cable technology at its finest!

## Channel Usage
![Channel Interference](/images/channelUsage.png)

## Channel Interference
![Channel Interference](/images/channelInterference.png)

## WiFi Transmission by Network
![Retries](/images/wifiXmit.png)

## WiFi Retries
![Retries](/images/retries.png)

## Airmax S/N and Airtime
![Airmad](/images/airmaxSN.png)




# Troubleshooting - Notes



• if some of your items randomly fail with 'Cannot read data from SSH server' (in the UI or in  /var/log/zabbix/zabbix_server.log), the likely culprit is an outdated version of libssh, which sometimes returns an error code even on success.  You have to compile the last version from sources from libssh.org and recompile I'm afraid..  This was a problem on Raspbian buster for libssh 0.8.x and is confirmed fixed with libssh 0.9.5 at least.  
 
• SSH to Unifi devices is invoked with the SSH option "-o StrictHostKeyChecking=accept-new" which means it will automatically accept their SSH host key on first connection to that IP or Host Name.  The default SSH setting is to ask for the user's confirmation on first connection but I deemed the extra convenience of not having to do this to be worth it in the context of a Home/Small Business Unifi setup

• The reason for the existence of the mca-dump-short external script instead of using SSH items directly if you are wondering is that there is a 64k limit to ssh.run items in zabbix, which we run into running mca-dump on large switches for ex. To raise that limit in Zabbix you have to recompile from sources and I didn't want to have that dependency.  The only reliable way I found around this is to run an external script to retrieve the mca-dump data from device, and then post-process it with jq to make the data < 64k on the way into Zabbix


# Future Additions

## Auto-discovery of devices based on controller connection

i.e automatically created all the proper hosts connected to the proper templates via a single connection to the Unifi controller

## Better SSH debugging

Most of the pain in setting those templates up is debugging the SSH connections..  Add pre-processing to check for valid json on mca-dump-short to all templates


## Moar data!

There is a mountain of information to be retrieved from devices.  I added what made most sense to me, but let me know if you would like to see added.  Also there is potential for quite a few more triggers..


