#!/bin/bash
# Partitioning and formatting
stat /dev/sdb > /dev/null 2>&1 && (stat /dev/sdb1 > /dev/null 2>&1 || (echo 'start=2048, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' | sfdisk --label gpt /dev/sdb && mkfs.ext4 -F -L DATA /dev/sdb1))
# Adding mount point
(lsblk -o label | grep -Fx DATA > /dev/null) && (echo; echo 'LABEL=DATA /opt ext4 defaults 0 1') | tee /etc/fstab
mount -a
# Adding TCPDump service, tcpreplay
apt -y install tcpreplay
mkdir -p /opt/ctf_toolbox/_data/
chgrp tcpdump /opt/ctf_toolbox/_data/
chmod g+rwx /opt/ctf_toolbox/_data/
cat << EOF | tee /etc/systemd/system/tcpdump.service # -i is interface, -G is tick size in s, -C is filesize
[Unit]
Description="Systemd script for tcpdump"
After=network.target network-online.target
Wants=network-online.target
[Service]
User=root
ExecStart=/bin/bash -lc '/usr/bin/tcpdump -i ens4 -C 1024 -G 180 -w "/opt/ctf_toolbox/_data/dump-%%s.pcap"'
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
# Installing Toolbox
cd /opt
git clone --recurse-submodules --shallow-submodules --depth 1 https://github.com/mullerdavid/ctf_toolbox.git
cd ctf_toolbox
docker compose up -d --build

# Rebuild Tulip on config change
# docker compose up -d --build api

# Splitting packets, adding fake ethernet frame
# editcap -i 180 big.pcapng dump.pcap
# (for file in *.pcap; do tcprewrite --dlt=enet --enet-dmac=00:11:22:33:44:55 --enet-smac=66:77:88:99:AA:BB --infile="$file" --outfile="eth_$file"; done) 
