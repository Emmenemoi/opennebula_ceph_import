# Opennebula Ceph images import

Import existing rbd images from one source to another, using diff export.

Using the "--live" option, as soon as the diff export cycle takes less than x sec, it pauses to allow you to stop the original VM (stop I/O), do the last sync and start it in OpenNebula.

