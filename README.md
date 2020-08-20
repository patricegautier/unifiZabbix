# unifiZabbix
Templates to monitor unifi and other UBNT devices in Zabbix

I am currently running those on the current version of the base software as of August 2020: Zabbix 5.0.2, Unifi 4.3.20 and AirMax 8.7.1, UDMP 1.8.0, controller 6.0.13

# SSH

These templates use public key SSH to access APs, Switches, Routers, AirMax stations and retrieve data directly, using the mca-dump or mca-status utility. You need to setup SSH access on your Zabbix server:

1/ You should generate a new key pair for this.  Zabbix is finicky and this is the specific way I needed to run the generation get a workable keypair (no passphrase, pem format):

ssh-keygen -P "" -t rsa  -m pem -f zb_id_rsa

put that keypair somewhere on your zabbix server.

You will need to specifically enable SSH access to the unifi devices.  There is one setting in the controller UI for devices at large in Settings > Site and one for the UDMP in the UDMP advanced settings which is separate.  The controller has handy UI to install your public key on all the devices, you will need to do it by hand on UDMPs and AirMax devices.  ssh-copy-id helps there, esp. on the UDMP since those will embarrasingly wipe all your keys at every firmware update.

Permissions can get in the way so check that your zabbix server can actually get the SSH access with:

sudo -u zabbix ssh -i my-key-pair yourUserName@oneOfYouUnifiDevicesIP
  
If you are set up correctly that should log you in without asking for a password

2/ You then need to point Zabbix to this:

In your Zabbix conf file (/etc/zabbix/zabbix_server.conf typically) add:

SSHKeyLocation=<the path to your keys>

and in zabbix Macros (in Zabbix's Web UI Administration > General > Macros) set:

{$UNIFI_USER} to your SSH user name
{$UNIFI_PUB_KEY} to zb_id_rsa.pub
{$UNIFI_PRIV_KEY} to zb_id_rsa


# Templates

To get started import unifyTemplates.xml into Zabbix.  

You should now have the following templates available, and it should be pretty self explanatory what you need to link them to:

Unifi AP

Unifi Switch

Unifi Router

Unifi USG

Unifi UDMP

UBNT AirMax

Unifi WiFi Site
This one is a bit special and meant to aggregate WiFi traffic across your wifi networks.  Just assign it to one of the APs that can see all the networks in question and assign the {$UNIFI_AP_GROUP} macro for that host to the name of a group that contains all the APs for that site.


The templates surrounded by dashes (- Unifi base -, - Unifi host - and - Unifi router -) are just there to factor things out and not meant to be assigned directly to hosts in Zabbix

# Macros

In Administration > General > Macros, you need to set a vlues for the following macros:

{$UNIFI_USER} The username that will let the zabbix server (or proxy) in to your unifi devices via SSH

{$UNIFI_PUB_KEY} The public key file to be able to SSH into your unifi devices. As an example, that macro is set to 'zb_id_rsa.pub' on my system. The actual public key should be added to the SSH keys in the Unifi controller SSH area.  The public key file should also be on your Zabbix server and proxies and the path to that in the Zabbix conf file, typicially /etc/Zabbix/zabbix_server.conf.  The entry should look like. SSHKeyLocation=/home/pi/.ssh/zabbix.

{$UNIFI_PRIV_KEY} The private key filename to be able to SSH into your Unifi devices.  As an example, that macro is set to 'zb_id_rsa' on my system. The actual private key file needs to be on your Zabbix server and proxies, and the path to that in the Zabbix conf file, typicially /etc/Zabbix/zabbix_server.conf.  As an example. I have this set to:  SSHKeyLocation=/home/pi/.ssh/zabbix

{$UNIFI_CHECK_FREQUENCY} I have this set to '1m'

{$UNIFI_ALERT_TEMP} The temperature in Celsius above which to alert.  I have to this to '90'.

{$UNIFI_ALERT_PERIOD} The period after which to alert for most checks. I have this set to '10m'.

{$UNIFI_SMOOTHING_COUNT} I have this set to '#5'
{$UNIFI_SMOOTHING_PERIOD}  I have this set to '10m'

Those two are used to create moving averages that make graphs far easier to read

# Graphs

If everything is working you should be able to see data flowing in the Monitoring > Latest Data section of Zabbix.  Time to set up some graphs..  Unfortunately Zabbix doesn't to have a good way to share graphs as it does for templates, so here is a quick rundown of what I have setup..:



# Limitations

1/ Some devices periodically refuse to answer.  This typically resolves in a few minutes but I haven't been able to get to the root cause.

2/ There is a 64k limit to ssh.run items in zabbix, which we run into running mca-dump on large switches for ex.  The commands in the template have some potentially brittle sed scripting to work around that limitation.  This might manifest itself in items becoming supported items with a 'unable to read JSON path - unexpected end of string'

To raise that limit in Zabbix you have to recompile and I didn't want to have that dependency.  If anyone can think of another more stable and convenient workaround, please let me know!  Gzip comes to mind and is present on BusyBox which is the OS that those Unifi devices run, but I haven't found a way to decompress it on the zabbix side and still use the JSON path preprocessing option


 
