
## UNDER DEVEVELOPMENT ##

# Virtual Ceph images import

Import existing images (rbd, lvm or zfs) from one source to rbd image (raw or cinder), using diff with rbd or rsync.

Using the "--live" option, as soon as the diff export cycle takes less than x sec, it pauses to allow you to stop the original VM (stop I/O), do the last sync and start it in the target env (OpenNebula, oVirt or other).

