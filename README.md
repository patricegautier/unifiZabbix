# unifiZabbix
Templates to monitor unifi and other UBNT devices in Zabbix

I am currently running those on the current version of the base software as of August 2020: Zabbix 5.0.2, Unifi 4.3.20 and AirMax 8.7.1.

# SSH

These templates use public key SSH to access APs, Switches, Routers, AirMax stations and retrieve data directly, using the mca-dump or mca-status utility. You need to setup SSH access on your Zabbix server:

1/ You should generate a new key pair for this.  Zabbix is finicky and this is the specific way I needed to run the generation get a workable keypair (no passphrase, pem format):

ssh-keygen -P "" -t rsa  -m pem -f zb_id_rsa

put that keypair where your zabbix server can get to it.

You will need to specifically enable SSH access to the unifi devices.  There is one setting in the controller UI for devices at large in Settings > Site and one for the UDMP in the UDMP advanced settings which is separate.  The controller has handy UI to install your public key on all the devices, you will need to do it by hand on UDMPs and AirMax devices.  ssh-copy-id helps there, esp. on the UDMP since those will embarrasingly wipe all your keys at every firmware update.

Permissions can get in the way so check that your zabbix server can actually get the SSH access with:

sudo -u zabbix ssh -i my-key-pair <yourUserName>@<oneOfYouUnifiDevicesIP>
  
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

You should now have the following templates available.

Unifi Base

Unifi Host

Unifi AP

Unifi Switch

Unifi Router

Unifi USG

Unifi UDMP

Unifi WiFi Site

UBNT AirMax


# Limitations

There is a 64k limit to ssh.run items in zabbix, which we run into running mca-dump on large switches for ex.  The commands in the template have some potentially brittle sed scripting to work around that limitation.  This might manifest itself in items becoming supported items with a 'unable to read JSON path - unexpected end of string'

To raise that limit in Zabbix you have to recompile and I didn't want to have that dependency.  If anyone can think of another more stable and convenient workaround, please let me know!  Gzip comes to mind and is present on BusyBox which is the OS that those Unifi devices run, but I haven't found a way to decompress it on the zabbix side and still use the JSON path preprocessing option


 
