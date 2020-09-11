# unifiZabbix

This projet contains a collection of Templates to monitor Unifi and other UBNT devices with Zabbix: APs, Switches, Routers (USG and UDMP), AirMax devices, and NVRs

I am currently running those on the current version of the base software as of August 2020: Zabbix 5.0.2, Unifi 4.3.20 and AirMax 8.7.1, UDMP 1.8.0, controller 6.0.13

# BREAKING:  it turns out the zabbix export feature does not export the entirety of the templates and they will not work after being imported on the other side.   Please hold on using this package for now.

# Templates

To get started import unifyTemplates.xml into Zabbix.  

You should now have the following templates available, and it should be pretty self explanatory what type of device you need to link them to in Zabbix.

### Unifi AP

### Unifi Switch

### Unifi Router

### Unifi USG

### Unifi UDMP

### UBNT AirMax

### Unifi WiFi Site

This one is a bit special and meant to aggregate WiFi traffic across your wifi networks.  Just assign it to one of the APs that can see all the networks in question and assign the {$UNIFI_AP_GROUP} macro for that host to the name of a group that contains all the APs for that site.


The templates surrounded by dashes (- Unifi base -, - Unifi host - and - Unifi router -) are there to factor things out and not meant to be assigned directly to hosts in Zabbix. They have to be on your system, but you can ignore them

# SSH

These templates use public key SSH to access APs, Switches, Routers, AirMax stations and retrieve data directly, using the mca-dump or mca-status command line utility. You need to setup SSH access on your Zabbix server:

1/ You should generate a new key pair for this.  Zabbix is finicky and this is the specific way I needed to run the generation get a workable keypair (no passphrase, pem format):

> ssh-keygen -P "" -t rsa  -m pem -f zb_id_rsa

put that keypair somewhere on your zabbix server (I put it in ~/.ssh/zabbix/)

You will need to specifically enable SSH access to the unifi devices.  There is one setting in the controller UI for devices at large in Settings > Site and one for the UDMP in the UDMP advanced settings which is separate.  The controller has handy UI to install your public key on all the devices, you will need to do it by hand on UDMPs and AirMax devices.  *ssh-copy-id* helps there, esp. on the UDMP since those will embarrasingly wipe all your keys at every firmware update and reboot (seriously UBNT).

Permissions can get in the way so check that your zabbix server can actually get the SSH access with:

> sudo -u zabbix ssh -i my-key-pair yourUserName@oneOfYouUnifiDevicesIP
  
If you are set up correctly that should get you in without asking for a password

2/ You then need to point Zabbix to those keys.  In your Zabbix conf file (/etc/zabbix/zabbix_server.conf typically) add:

> SSHKeyLocation=/the/path/to/your/keys

# Using SSH passwords instead of key pairs

If you would rather use passwords, it's fairly simple to switch.  You only need to modify one spot.  Go to Configuration > Templates and select the '- Unifi Base -' template. Click on the Items tab, you should see one SSH agent entry called 'mca-dump'. Select that and you will see this:

![Key Pair](/images/keypair.png)

Change that section to:

![Password](/images/password.png)


Save and set up the {$UNIFI_PW} macro in General > Macros to your chosen password and it should automaticaly apply to all the Unifi devices that you have assigned one of Unifi templates of this package.

If you use the UBNT Airmax template, you will have to do the same with the mca-status item.

# Macros

In Zabbix, in Administration > General > Macros, you will need to set a value for __*all*__ the following macros:

## {$UNIFI_USER}
The username that will let the zabbix server (or proxy) log in to your unifi devices via SSH

## {$UNIFI_PUB_KEY}
The public key file to be able to SSH into your unifi devices. As an example, that macro is set to 'zb_id_rsa.pub' on my system. The actual public key should be added to the SSH keys in the Unifi controller SSH area.  The public key file should also be on your Zabbix server and proxies and the path to that in the Zabbix conf file, typicially /etc/Zabbix/zabbix_server.conf.  The entry should look like: SSHKeyLocation=/home/pi/.ssh/zabbix.

## {$UNIFI_PRIV_KEY}
The private key filename to be able to SSH into your Unifi devices.  As an example, that macro is set to 'zb_id_rsa' on my system. The actual private key file needs to be on your Zabbix server and proxies, and the path to that in the Zabbix conf file, typicially /etc/Zabbix/zabbix_server.conf.  As an example. I have this set to:  SSHKeyLocation=/home/pi/.ssh/zabbix

## {$UNIFI_CHECK_FREQUENCY}
I have this set to '1m'

## {$UNIFI_ALERT_TEMP}
The temperature in Celsius above which to alert.  I have set this to '90'.

## {$UNIFI_ALERT_PERIOD}
The period after which to alert for most checks. I have this set to '10m'.

## {$UNIFI_SMOOTHING_COUNT}
I have this set to '#5'

## {$UNIFI_SMOOTHING_PERIOD}
I have this set to '10m'

Those last two are used to create moving averages that make graphs far easier to read.

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




# Limitations

1/ You may seem some devices periodically time out.  This resolves usually at the next check but I haven't been able to get to the root cause.

2/ There is a 64k limit to ssh.run items in zabbix, which we run into running mca-dump on large switches for ex.  The commands in the template have some potentially brittle sed scripting to work around that limitation.  This might manifest itself in some of the Zabbix items becoming unsupported with a *'unable to read JSON path - unexpected end of string'* error.

To raise that limit in Zabbix you have to recompile and I didn't want to have that dependency.  If anyone can think of another more stable and convenient workaround, please let me know!  Gzip comes to mind and is present on BusyBox which is the OS that those Unifi devices run, but I haven't found a way to decompress it on the zabbix side and still use the JSON path preprocessing option


 
