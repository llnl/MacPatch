[Unit]
Description=MacPatch Rsync Server
After=syslog.target network.target
ConditionPathExists=/opt/MacPatch/Server/etc/rsyncd.conf

[Service]
ExecStart=/usr/bin/rsync --daemon --no-detach --config=/opt/MacPatch/Server/etc/rsyncd.conf

[Install]
WantedBy=multi-user.target