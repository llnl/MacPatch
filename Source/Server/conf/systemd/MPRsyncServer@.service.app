[Unit]
Description=MacPatch fast remote file copy program daemon
ConditionPathExists=/opt/MacPatch/Server/etc/rsyncd.conf

[Service]
ExecStart=/usr/bin/rsync --daemon --no-detach --config=/opt/MacPatch/Server/etc/rsyncd.conf
StandardInput=socket
