[Unit]
Description=The MacPatch NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/opt/MacPatch/Server/nginx/logs/nginx.pid
ExecStartPre=/opt/MacPatch/Server/nginx/sbin/nginx -t
ExecStart=/opt/MacPatch/Server/nginx/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target