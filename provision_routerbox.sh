#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
# Partitioning and formatting
stat /dev/sdb > /dev/null 2>&1 && (stat /dev/sdb1 > /dev/null 2>&1 || (echo 'start=2048, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' | sfdisk --label gpt /dev/sdb && mkfs.ext4 -F -L DATA /dev/sdb1))
# Adding mount point
(lsblk -o label | grep -Fx DATA > /dev/null) && (echo; echo 'LABEL=DATA /opt ext4 defaults 0 1') | tee /etc/fstab
mount -a
# Installing packet capture utilities
apt update
apt -y install tcpdump tcpreplay wireshark-common
# Adding packet forwarder service
apt -y install autossh lftp proxychains
mkdir -p /opt/packet_forward/pcap
cd /opt/packet_forward/
cat << 'EOF' | tee run.sh
#!/bin/bash
(ss -tulpn | grep LISTEN | grep 127.0.0.1:9050) || \
    autossh -M 0 -i /opt/packet_forward/key -o StrictHostKeyChecking=no -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -N -f -D 9050 ubuntu@129.241.150.39
cd /opt/packet_forward/pcap
function process_pcap {
    filename=$1
    newfilename="/opt/ctf_toolbox/_data/${filename%.pcapng}.pcap"
    if [[ ! -f "$newfilename" ]]; then
        filesize=$(stat -c%s "$filename")
        if [[ $filesize -gt 50000000 ]]; then
            editcap -F libpcap "$filename" "$newfilename"
            echo Crated "$newfilename"
        fi
    fi

} 
while true
do
    sleep 5
    proxychains lftp  -f "
    open 172.16.13.1
    user user 123
    lcd /opt/packet_forward/pcap
    mirror --continue --delete --verbose --parallel=5 . .
    bye
    "
    for filename in *.pcapng; do (process_pcap "$filename"); done
done
EOF
chmod +x run.sh
cat << EOF | tee key
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAqfFTWyO3AA74MHzA+3fkRWjWgtKzsbKdCyJarqfgFdFDdAra
2CjhvaclbKr2WlSf1QqgWSHA1oB52EwWP3vgXPCl03KOBXXpxMnXS9g6gH0W9+T2
2OFDPfLhx9+8OYgp+bg6wx+YaNN3r5zUpDb0aePpEi5anUadKfo7cG8vK9IB0NZ4
Yt1ah0yqr+WVBixiEZTwCOu1pi8/uNDMRgzgrkQxnL8B99zWcwXID1I5fY+9PFzU
Gd6ZBcpX11//JANFB/5G4snNwVSiIYAuI2s/faHuB7uKC6QpUydIVTI75bfrjV4K
ARRJvU0ECLsyFuL04EqOSYTIpV8Zg1A6jQI5zwIDAQABAoIBADX2RSupeZBxMGnl
EzpGZZuMoKDF2v1P5AIHFJhlAgirfCm60KbWxGd+Tanl13fzaxUw3J2w1BTIkugV
sPLTmPiqCV3NAD/Ho0UzekPBE0J9de+dKqzPSpS/LOZUquXx0LJUx4Px4mlWzKhc
ukCymoWNMxLs2SUbqQgNRxZ6l5XoAuRw2s19qYm/AsdmJrrVZnswX9GsyJSjN4OD
IK3vMiujYrUzAhfnU/JoxD9LuR+8rc5YKctzYCcpSleM9Rj/op4gnJ2PYMXmc8f5
fdf1X8tgs9xC2hKDx4m8gv16kWpipiCiprx1ubvxXo8yp507BUiJkx2iPfa3pXPb
9GNiSzECgYEA1BaB7rfsY0WMVrKHMKDvuW1tpQwr5ABLxoWlBy2ioAaQ8R5ZBCjg
83pwz5Tbq1MukfQx7E7Ss1s7vXgtUzzXxWL5nhf0M/j+hxLbSRFiiSIUwRYxYJy4
lsxB2LmNDfhfFIdlTB4GDGwkBB6EfLW3VyfMj1MJ+0R4fxKWkBSWEG0CgYEAzSD0
a8Uptq4GV+WKgTf9SdYjK/YsOBRpBQmbkOw6hTcFeQaIiyUN5fOHh2ycllcvYIk4
Q3I2ltRwa6n6DP069FFNQVtbEibsBOJXkWzUrclNQ9AeirLtHyq0wt3VkEfJ9fVz
/Rq6UHy+fBUCSv7F38MV86eoZckmnqEHgi2LpasCgYEA0is7twQsDHPvDjr8HQRe
irIV5WiaVea1MJVfZC2k6k+XcllQfP7FbIH5KLuqs6xKifgjQLkbswDFwoxE3id8
6u2Zz0CNjrNABzp4c3/21U4govcLF2I2ybi/x7SYQy/NiNpjV3qpI8ZGKo7TW4H3
nTajT6RKT+UaQ1J4QW8lBkECgYAIEOCrkDAot8UWFbeRhzMVgS8W3nI0rlDG2u7c
Dv3qGRTFAoXB+u4F+cJ9h77MhpcdU6f7tvUAj0/wW9myQw7bZosEI+R73T3wnznU
RRRD1SONpBRfXdPHIvXCp9hq+PevDTzHWhKzcYRH+seBTW1YdCJb117eyb8UA774
1nOkSwKBgAcUTEr1Vc8kglhHYDcraqb2vgBmmXkMnOcinbL9NFUMo1cL5/DJgG1g
PJzpMnzrLrA7hD4phkuUGvsIovV8pc0GgnUKjNbZZvhsbS6IdKI9Ppoo47utrE1A
k+CbEyjEgi1AWgRSPXkgwh7LhJOTxPr8gmdOo98cUA0y7lHU1WA1
-----END RSA PRIVATE KEY-----
EOF
chmod 600 key
# screen -d -m /opt/packet_forward/run.sh
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
cat << EOF | tee /etc/docker/daemon.json
{
  "data-root": "/opt/docker",
  "default-address-pools": [
    {"base":"10.217.0.0/16","size":16},
    {"base":"10.218.0.0/16","size":16},
    {"base":"10.219.0.0/16","size":16},
    {"base":"10.220.0.0/16","size":16},
    {"base":"10.221.0.0/16","size":16},
    {"base":"10.222.0.0/16","size":16},
    {"base":"10.223.0.0/16","size":16},
    {"base":"10.224.0.0/16","size":16},
    {"base":"10.225.0.0/16","size":16},
    {"base":"10.226.0.0/16","size":16},
    {"base":"10.227.0.0/16","size":16},
    {"base":"10.228.0.0/16","size":16},
    {"base":"10.229.0.0/16","size":16},
    {"base":"10.230.0.0/16","size":16},
    {"base":"192.168.0.0/16","size":20}
  ]
}
EOF
rm -r /var/lib/docker
systemctl restart docker.service
# Installing Toolbox
cd /opt/
git clone --recurse-submodules --shallow-submodules --depth 1 https://github.com/mullerdavid/ctf_toolbox.git
cd ctf_toolbox
docker compose up -d --build
# Adding TCPDump service, 
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

# Rebuild Tulip on config change
# docker compose up -d --build api

# Splitting packets, adding fake ethernet frame
# editcap -i 180 big.pcapng dump.pcap
# (for file in *.pcap; do tcprewrite --dlt=enet --enet-dmac=00:11:22:33:44:55 --enet-smac=66:77:88:99:AA:BB --infile="$file" --outfile="eth_$file"; done) 
