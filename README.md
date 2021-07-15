# unifiZabbix

This projet contains a collection of Templates to monitor Unifi and other UBNT devices with Zabbix: APs, Switches, Routers (USG and UDMP), AirMax devices, and NVRs

I am currently running those on the current versions of the base software as of Dec 2020: Zabbix 5.2, a mix of Unifi 4.x and 5.x APs and switches, AirMax 8.7.1, UDMP 1.8.3, controller 6.0.41


# Setup

## Zabbix 5.2 

given I am exporting those templates from 5.2.3 as of now, you will need 5.2 minimum to be able to import the templates. 


## Install jq on your Zabbix server

You need to install jq on your system: https://stedolan.github.io/jq/

On Raspbian, this can be done with:

	apt-get install jq

## Install mca-dump-short script as a Zabbix external script

You need to install mca-dump-short.sh in Zabbix's external script directory

Please confirm where that directory is from the variable ExternalScripts in your zabbix server conf at /etc/zabbix/zabbix_server.conf.  On my system this is set to:

	ExternalScripts=/usr/lib/zabbix/externalscripts

After cp-ing the script to that directory, make sure you have the permissions necessary for zabbix to execute this script:

	chown zabbix:zabbix /usr/lib/zabbix/externalscripts /usr/lib/zabbix/externalscripts/mca-dump-short.sh
	chmod a+x /usr/lib/zabbix/externalscripts /usr/lib/zabbix/externalscripts/mca-dump-short.sh


## Import the Unifi templates into Zabbix

Import zbx_export_templates.xml into Zabbix, from Configuration > Templates > Import

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
	SunMax SolarPoint
	Unifi SSH Host


• You will need to assign the templates with the matching type to hosts you have to create in Zabbix for your unifi devices.  Use the 'Agent' interface in Zabbix with the proper IP or DNS entry.

A couple of things on top of that:

• Unifi SSH Host: assign that one to all your Unifi infrastructure devices, on top of the template for that specific type.  <i>(In a perfect world, I would have had the specific templates inherit from that one and all the right items appear that way but Zabbix does not support exporting and reimporting a template hierarchy as of 5.2.  Assigning both templates is the work-around)</i>

• Unifi Wifi Site is meant to aggregate WiFi traffic across your wifi networks for a Unifi site.  Just assign it to one of the APs that can see all the networks in question and assign the {$AP_GROUP} macro for that host to the name of a zabbix host group that contains all the APs for that site.

## Setup SSH from your Zabbix server to your Unifi devices via public/private keypair

These templates use public key SSH to access APs, Switches, Routers, AirMax stations and retrieve data directly, using the mca-dump or mca-status command line utility.  Your zabbix server (or your proxies if you use those) will need public key SSH access to all the unifi devices they are monitoring:

1/ You should generate a new key pair for this.  

The templates are set up to work with a public-private key pair.   For a primer on that you can check out for ex https://www.redhat.com/sysadmin/passwordless-ssh.  Since you need zabbix to be able to use those without you in front of the keyboard, you need an empty passphrase.

Zabbix is finicky and this is the specific way I needed to run the generation get a workable keypair (no passphrase, pem format). From your Zabbix server, run:

	sudo -u zabbix ssh-keygen -P "" -t rsa  -m pem -f zb_id_rsa

put that keypair somewhere on your zabbix server (I put it in ~/.ssh/zabbix/).  Check the permissions on those keys and directory.  This is what I have end up with for ex:

	pi@pi:~/.ssh/zabbix $ ls -l
	total 20
	-rw------- 1 zabbix zabbix 1675 Jul 23 18:57 zb_id_rsa
	-rw-r--r-- 1 zabbix zabbix 391 Jul 23 18:57 zb_id_rsa.pub


2/ You will need to specifically enable SSH access on the unifi devices.  

For most devices,  there is one setting in the Unifi controller UI in Settings > Site and one for the UDMP in the UDMP advanced settings which is separate.  

3/ You then need to send your public key to all the devices you want to monitor
 
For managed devices (APs, Switches), the Unifi controller has handy UI to install your public key on all the devices.

for UDMPs and AirMax devices, you will need to do it by hand.  *ssh-copy-id* helps there, esp. on the UDMP since those will embarrasingly wipe all your keys at every firmware update and reboot (seriously UBNT):  

	sudo -u zabbix ssh-copy-id -i <path_to_your_privateKey> yourUserName@oneOfYourUnifiDevicesIP

I have a more sophisticated script I use to do this at https://github.com/patricegautier/certRenewalScripts/blob/master/updatePublicKey.sh


3/ So now check that your zabbix server can actually get in with SSH with:

	sudo -u zabbix ssh -i <fullPathToYourPrivateKey> yourUserName@oneOfYourUnifiDevicesIP
  
If you are set up correctly that should get you in *without asking for a password*

You can also check that the script used to retrieve data is working correctly for a given device with:

	sudo -u zabbix /usr/lib/zabbix/externalscripts/mca-dump-short.sh -d <theDeviceIP> -u <yourUnifiUserName> -i <fullPathToYourPrivateKey> -t <UDMP|AP|SWITCH|CK>

You should get a JSON document in return.

If you use a Zabbix proxy, it will initiate the connection to the hosts it monitors, so you need to run those tests there.


4/ You then need to point Zabbix to those keys.  

In your Zabbix conf file (/etc/zabbix/zabbix_server.conf typically) add:

	SSHKeyLocation=/the/path/to/your/keys

in my case I have:
	
	SSHKeyLocation=/home/pi/.ssh/zabbix


## Macros

In Zabbix, in Administration > General > Macros, you will need to set a value for __*all*__ the following macros:

### {$UNIFI_USER}
The username that will let the zabbix server (or proxy) log in to your unifi devices via SSH

### {$UNIFI_SSH_PRIV_KEY_PATH}
The full path where to find the public private key pair to be able to SSH into your Unifi devices.  The private key should be in the SSHKeyLocation directory from your zabbix conf file.  For my system for ex, this is set to /home/pi/.ssh/zabbix/zb_id_rsa

### {$UNIFI_PRIV_KEY}
The file name for your private key in SSHKeyLocation.  For me this is set to zb_id_rsa

### {$UNIFI_PUB_KEY}
The file name for your public key in SSHKeyLocation.  For me this is set to zb_id_rsa.pub

### {$UNIFI_CHECK_FREQUENCY}
I have this set to '1m'

### {$UNIFI_ALERT_TEMP}
The temperature in Celsius above which to alert.  I have set this to '90'.

### {$UNIFI_ALERT_PERIOD}
The period after which to alert for most checks. I have this set to '10m'.  The triggers on this period are level 'Warning'

### {$UNIFI_ALERT_LONG_PERIOD}
The period after which to alert for checks that failed for an extended period pf time. I have this set to '6h'.  The triggers on this period are level 'Average'

### {$PROTECT_CAMERA_PASSWORD}
Set this to your cameras' password.  There's UI in the protect controller to set this on all cameras at once.  

You will also need to enable SSH for cameras, the instructions are at:

	https://help.ui.com/hc/en-us/articles/360015877853-UniFi-Protect-Enabling-Camera-SSH-Access


### {$PROTECT_LOW_BANDWIDTH}
The threshold of camera outoing bandwidth below which to alert.  I have this set to 500000 i.e 500kbps.

### {$UNIFI_SMOOTHING_PERIOD}
I have defined some moving average items with the suffix _smooth to help make graphs easier to read.  This is set to '10m' for me.

### {$UNIFI_LOAD_AVERAGE_MEDIUM}
The load average value above which to issue a info.  The consensus is 1 for this.  Note that for switches and APs this value has less meaning since they process packets with specialized HW and this macro is overridden in the template to avoid too many warnings

### {$UNIFI_LOAD_AVERAGE_HIGH}
The load average value above which to issue a warning.  I have this set to 2.  Note that for switches and APs this value has less meaning since they process packets with specialized HW and this macro is overridden in the template to avoid too many warnings



# SUCCESS!

If you got this far, congratulations the install is complete!  Now for the funner part:


# Graphs

If everything is working you should be able to see data flowing in the Monitoring > Latest Data section of Zabbix.  Time to set up some graphs..  Unfortunately Zabbix doesn't to have a good way to share graphs as it does for templates, so here is a quick rundown of what I have setup..:


## UDMP|USG Wan Download
![Wan Download](/images/wanDownload.png)

## UDMP|USG Wan Upload
![Wan Upload](/images/wanUpload.png)

Observe the tight correlation between upload bandwidt and latency.. Cable technology at its finest!

## Router: InterVLAN traffic by network
![InterVLAN](/images/intervlan.png)

I have found this one to be useful to get router usage down

## Total Switch Traffic by Switch
![Switch Traffic](/images/totalSwitch.png)

Useful to point to potential bottlenecks

## WiFi Channel Usage by AP
![Channel Interference](/images/channelUsage.png)

## WiFi Channel Interference bu AP
![Channel Interference](/images/channelInterference.png)

## WiFi Transmission by Network
![Retries](/images/wifiXmit.png)

## WiFi Retries
![Retries](/images/retries.png)

## Airmax S/N and Airtime by AirMax device
![Airmad](/images/airmaxSN.png)


# SunMax Solarpoint Support

## Install solarpointBattery.sh

Following the same steps as mca-dump-short.sh above, install solarpointBattery.sh as a Zabbix external script

## Macros

The SunMax SolarPoints do not support SSH, so you'll have to set up the following macros seperately, either in Administration > General > Macros or on the host directly depending on your case:

### {$SOLARPOINT_USERNAME}
The username that will let the zabbix server (or proxy) log in to the SolarPoint device

### {$SOLARPOINT_PASSWORD}
The password that will let the zabbix server (or proxy) log in to the SolarPoint device

That will give you access to power production and consumption, as well as set a trigger on PoE ports being suspended

## Some Graph Examples

## Power Production and Consumption
![Wan Download](/images/power.png)

## Battery Voltage
![Wan Download](/images/voltage.png)







# Troubleshooting - Notes

• Your zabbix server log file (/var/log/zabbix/zabbix\_server.log usually) can be a good source of debugging info, esp if you set DebugLevel=4 in  /etc/zabbix/zabbix_server.conf. Restart the Zabbix server with
	
		 sudo service zabbix-server restart

• Macros Cheat Sheet

This is my set of values

![Macros](/images/macros.png)		 

• if some of your items randomly fail with 'Cannot read data from SSH server' (in the UI or in  /var/log/zabbix/zabbix_server.log), the likely culprit is an outdated version of libssh, which sometimes returns an error code even on success.  You have to compile the last version from sources from libssh.org and recompile I'm afraid..  This was a problem on Raspbian buster for libssh 0.8.x and is confirmed fixed with libssh 0.9.5 at least.  

• if you import fails with <i>'Invalid parameter "/interfaceid": cannot be empty.'</i>, it might be caused by the presence of an older version of the templates.  Remove them before re-importing.. 
 
• SSH to Unifi devices is invoked with the SSH option "-o StrictHostKeyChecking=accept-new" which means it will automatically accept their SSH host key on first connection to that IP or Host Name.  The default SSH setting is to ask for the user's confirmation on first connection but I deemed the extra convenience of not having to do this to be worth it in the context of a Home/Small Business Unifi setup

• The reason for the existence of the mca-dump-short external script instead of using SSH items directly if you are wondering is that there is a 64k limit to ssh.run items in zabbix, which we run into running mca-dump on large switches for ex. To raise that limit in Zabbix you have to recompile from sources and I didn't want to have that dependency.  The only reliable way I found around this is to run an external script to retrieve the mca-dump data from device, and then post-process it with jq to make the data < 64k on the way into Zabbix


# Future Additions

## Auto-discovery of devices based on controller connection

i.e automatically create all the proper hosts connected to the proper templates via a single connection to the Unifi controller

## Better SSH debugging

Most of the pain in setting those templates up is debugging the SSH connections..  Add pre-processing to check for valid json on mca-dump-short to all templates

## SolarPoint support

## Even Moar data!

There is a mountain of information to be retrieved from devices.  I added what made most sense to me, but let me know if you would like to see added.  Also there is potential for quite a few more triggers..


