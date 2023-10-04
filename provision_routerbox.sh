#!/bin/bash
# Partitioning and formatting
stat /dev/sdb > /dev/null 2>&1 && (stat /dev/sdb1 > /dev/null 2>&1 || (echo 'start=2048, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' | sfdisk --label gpt /dev/sdb && mkfs.ext4 -F -L DATA /dev/sdb1))
# Adding mount point
(lsblk -o label | grep -Fx DATA > /dev/null) && (echo; echo 'LABEL=DATA /opt ext4 defaults 0 1') | tee /etc/fstab
mount -a
# Adding TCPDump service, tcpreplay
apt -y install tcpreplay
mkdir /opt/capture
chgrp tcpdump /opt/capture
chmod g+rwx /opt/capture
cat << EOF | tee /etc/systemd/system/tcpdump.service # -i is interface, -G is tick size in s, -C is filesize
[Unit]
Description="Systemd script for tcpdump"
After=network.target network-online.target
Wants=network-online.target
[Service]
User=root
ExecStart=/bin/bash -lc '/usr/bin/tcpdump -i ens4 -C 1024 -G 180 -w "/opt/capture/dump-%%s.pcap"'
SuccessExitStatus=143
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable tcpdump.service
# Starting TCPDump service
# systemctl start tcpdump.service
# Installing yq
mkdir /opt/bin
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(dpkg --print-architecture) -O /opt/bin/yq && chmod +x /opt/bin/yq
# Installing ElasticSearch
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor --yes -o /usr/share/keyrings/elasticsearch-keyring.gpg
apt -y install apt-transport-https
echo 'deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main' | tee /etc/apt/sources.list.d/elastic-8.x.list
apt update && apt -y install elasticsearch
# Configuring ElasticSearch
(echo; echo -Xms32g; echo -Xmx32g) | tee -a /etc/elasticsearch/jvm.options
mkdir /opt/elasticsearch/
chown elasticsearch:elasticsearch /opt/elasticsearch/
cp -rp /var/lib/elasticsearch /opt/elasticsearch/data
cp -rp /var/log/elasticsearch /opt/elasticsearch/logs
sed -i -r -e 's/path\.data\:.*/path\.data\: \/opt\/elasticsearch\/data/g' -e 's/path\.logs\:.*/path\.logs\: \/opt\/elasticsearch\/logs/g' /etc/elasticsearch/elasticsearch.yml
sed -i -r -e 's/http\.host\:.*/http\.host\: 127.0.0.1/g' -e 's/enabled\:\s+true/enabled\: false/g' /etc/elasticsearch/elasticsearch.yml # Turning off security
systemctl daemon-reload
systemctl enable elasticsearch.service
systemctl start elasticsearch.service
curl http://localhost:9200
# Installing Arkime
wget https://s3.amazonaws.com/files.molo.ch/builds/ubuntu-22.04/arkime_4.5.0-1_amd64.deb
dpkg --force-overwrite -i arkime_4.5.0-1_amd64.deb
apt -y install -f
# Configuring Arkime, edit arkime credentials here
mkdir /opt/suricata
(echo; echo; echo; echo Password1; echo) | /opt/arkime/bin/Configure
/opt/arkime/db/db.pl http://localhost:9200 init --ifneeded
/opt/arkime/bin/arkime_add_user.sh ctf ctf Password1 --admin
sed -i -r -e 's/interface=.*/#interface=/g' -e 's/pcapWriteMethod=.*/pcapWriteMethod=null/g' -e 's/# cronQueries=.*/cronQueries=true/g' /opt/arkime/etc/config.ini
sed -i -r -e 's/# plugins=.*/plugins=suricata.so\nsuricataAlertFile=\/opt\/suricata\/eve.json/g' /opt/arkime/etc/config.ini
sed -i -r -e 's/ExecStart=.*/ExecStart=\/bin\/sh -c "\/opt\/arkime\/bin\/capture -c \/opt\/arkime\/etc\/config\.ini ${OPTIONS} -R \/opt\/suricata --monitor --skip >> \/opt\/arkime\/logs\/capture\.log 2>\&1"/g' /etc/systemd/system/arkimecapture.service
systemctl daemon-reload
systemctl enable arkimecapture.service
systemctl enable arkimeviewer.service
systemctl start arkimecapture.service
systemctl start arkimeviewer.service
# Installing Suricata
apt -y install suricata
# Configuring Suricata
mkdir /opt/suricata
/opt/bin/yq -i '.default-rule-path = "/var/lib/suricata/rules/"' /etc/suricata/suricata.yaml
/opt/bin/yq -i 'del(.af-packet)' /etc/suricata/suricata.yaml
/opt/bin/yq -i 'del(.outputs[] | select(.pcap-log)) | .outputs |= . + {"pcap-log": {"enabled": true, "limit": "32mb", "filename":"suricata-%t-%n.pcap", "mode": "multi", "use-stream-depth": false, "honor-pass-rules": false}}' /etc/suricata/suricata.yaml
sed -i -r -e 's/ExecStart=.*/ExecStart=\/bin\/sh -c "\/usr\/bin\/suricata -c \/etc\/suricata\/suricata.yaml -l \/opt\/suricata\/ -r \/opt\/capture --pcap-file-continuous --pcap-file-delete --runmode single --pidfile \/run\/suricata.pid"/g' -e 's/Type=.*/Type=simple/g' /lib/systemd/system/suricata.service
suricata-update update-sources
suricata-update enable-source et/open
suricata-update enable-source oisf/trafficid
suricata-update enable-source tgreen/hunting
suricata-update enable-source malsilo/win-malware
suricata-update enable-source stamus/lateral
suricata-update
systemctl daemon-reload
systemctl enable suricata.service
systemctl start suricata.service
# Installing Evebox
wget -qO - https://evebox.org/files/GPG-KEY-evebox | gpg --dearmor --yes -o /usr/share/keyrings/evebox-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/evebox-keyring.gpg] http://evebox.org/files/debian stable main' | tee /etc/apt/sources.list.d/evebox.list
apt update
apt -y install evebox
# Configuring Evebox
/opt/bin/yq -i '.input.enabled = true' /etc/evebox/evebox.yaml
/opt/bin/yq -i '.input.paths = ["/opt/suricata/eve.json"]' /etc/evebox/evebox.yaml
systemctl enable evebox
systemctl start evebox
# Installing Docker
wget -qO - https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /usr/share/keyrings/docker-keyring.gpg
echo 'deb [arch='$(dpkg --print-architecture)' signed-by=/usr/share/keyrings/docker-keyring.gpg] https://download.docker.com/linux/ubuntu '$(. /etc/os-release && echo "$VERSION_CODENAME")' stable' | tee /etc/apt/sources.list.d/docker.list
apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
mkdir /opt/docker
# Configuring Docker
(echo '{'; echo '  "data-root": "/opt/docker"'; echo '}') | tee /etc/docker/daemon.json
rm -r /var/lib/docker
systemctl restart docker.service
# Installing Tulip
cd /opt
git clone https://github.com/OpenAttackDefenseTools/tulip.git
cd tulip
# Configuring Tulip
sed -r -i -e '/vm_ip\s+=/,$d' services/configurations.py
cat << EOF | tee -a services/configurations.py # edit services here
vulnbox = "fd66:666:48::2"
testbox = "fd66:666:48::3"
services = [
		{"ip": vulnbox, "port": 5005, "name": "image-galoisry"},
		{"ip": vulnbox, "port": 3000, "name": "chatapp"},
		{"ip": vulnbox, "port": 1337, "name": "office_supplies"},
		{"ip": vulnbox, "port": 5000, "name": "jokes"},
		{"ip": vulnbox, "port": 13731, "name": "buerographie-app"},
		{"ip": vulnbox, "port": 5555, "name": "rsamail"},
		{"ip": vulnbox, "port": 3333, "name": "tic-tac-toe"},
		{"ip": vulnbox, "port": 12345, "name": "auction-service"},
		{"ip": vulnbox, "port": 12346, "name": "auction-service"},
		{"ip": vulnbox, "port": -1, "name": "other_vulnbox"},
		{"ip": testbox, "port": 19, "name": "demo"},
		{"ip": testbox, "port": -1, "name": "other_testbox"},
    ]
EOF
cat << EOF | tee .env # edit ctf details here
FLAG_REGEX="FAUST_[A-Za-z0-9/+]{32}"
TULIP_MONGO="mongo:27017"
# The location of your pcaps as seen by the host
TRAFFIC_DIR_HOST=/opt/suricata
# The location of your pcaps (and eve.json), as seen by the container
TRAFFIC_DIR_DOCKER="/traffic"
# Start time of the CTF (or network open if you prefer)
TICK_START="2023-09-23 12:00:00+00:00"
# Tick length in ms
TICK_LENGTH=180000
EOF
# Adding HAProxy auth for tulip, edit tulip credentials here
cp docker-compose.yml docker-compose-original.yml
mkdir /opt/tulip/haproxy
cat << EOF | tee /opt/tulip/haproxy/haproxy.cfg
defaults
	mode tcp
	timeout client 10s
	timeout connect 5s
	timeout server 10s
	timeout http-request 10s
	log stdout format raw local0 info
userlist credentials
	user ctf insecure-password Password1
frontend www-tulip
	bind :8006
	http-request auth unless { http_auth(credentials) }
	default_backend backend-tulip
frontend www-evebox
	bind :8007
	http-request auth unless { http_auth(credentials) }
	default_backend backend-evebox
backend backend-tulip
	mode http
	server tulip-frontend 127.0.0.1:3000
backend backend-evebox
	mode http
	server evebox-frontend 127.0.0.1:5636
EOF
/opt/bin/yq -i '.services.frontend.ports = ["127.0.0.1:3000:3000"]' docker-compose.yml
/opt/bin/yq -i '.services.haproxy = {"image": "haproxy", "restart": "always", "network_mode": "host", "volumes": ["/opt/tulip/haproxy:/usr/local/etc/haproxy:ro"]}' docker-compose.yml
docker compose up -d --build
# Rebuild Tulip on config change
# docker compose up -d --build api

# Splitting packets, adding fake ethernet frame
# editcap -i 180 big.pcapng dump.pcap
# (for file in *.pcap; do tcprewrite --dlt=enet --enet-dmac=00:11:22:33:44:55 --enet-smac=66:77:88:99:AA:BB --infile="$file" --outfile="eth_$file"; done) 
