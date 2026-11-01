> [!CAUTION]
> Although these scripts function correctly in my environment, they might not cover all use cases or handle every exception. Please use them with caution, particularly during remote operations.

# NetBird client for nanoKVM devices

This repository provides a nanoKVM-compatible NetBird client and an accompanying installation script for installing and updating the client on nanoKVM devices.
After installation, the client operates similarly to a NetBird client on any standard headless Linux distribution. 

Instructions for registering the nanoKVM device can be found at: https://docs.netbird.io/how-to/register-machines-using-setup-keys

> [!NOTE]
> * The NetBird client may occasionally exhibit slow performance. However, once it is connected, the network performance is fine.
> * The NetBird service startup script has been modified for use on the nanoKVM device. Do **NOT** use the NetBird client to manage the service.  
>   Use ```/etc/init.d/S98netbird [start|stop|restart|status]``` instead.

# Installation or updating

Both installation and updating can be performed using a single command

``` bash
curl -sL https://github.com/JoaoCostaIFG/nanoNetBird/releases/latest/download/install.sh | sh -
```

To avoid unnecessary downloads, if NetBird is already installed, the script verifies first if a newer version is available before downloading and applying the update.

> [!NOTE]
> The install/update script will look for the latest release within **this** repository. However, this repository is not (yet) automatically updated when new versions are published in the official NetBird repository, so it may lag behind.

# Files

The NetBird client is installed to ```/usr/sbin/netbird```, and its service startup script to ```/etc/init.d/S98netbird```.

The client configuration files can be found in ```/etc/netbird/``` (as usual).
