[Unit]
Description=MP Inventory Processing
After=syslog.target network.target

[Service]
Type=forking

ExecStart=/opt/MacPatch/Server/conf/scripts/systemd/MPInventoryD.sh start
ExecStop=/opt/MacPatch/Server/conf/scripts/systemd/MPInventoryD.sh stop

RemainAfterExit=yes

[Install]
WantedBy=multi-user.target