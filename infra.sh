#!/bin/bash

usage(){
echo "usage"
:
}

function ProgressBar {
# Process data
    let _progress=(${1}*100/${2}*100)/100
    let _done=(${_progress}*4)/10
    let _left=40-$_done
# Build progressbar string lengths
    _fill=$(printf "%${_done}s")
    _empty=$(printf "%${_left}s")


printf "\rProgress : [${_fill// /#}${_empty// /-}] ${_progress}%%"

}

checkRoot(){
if [[ $UID -ne 0 ]]
then
echo "You must have root previledge to run this"
exit 1
fi
}

checkRoot

freemem=$(free -m | awk 'NR==2 {print $4}')
freespace=$(df -h | awk '$6 == "/" {print $5}' | tr -d %)
version=$(hostnamectl | awk -F ':' '$1 == "  Operating System" {print  $2}')
ip4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
hostname="master-node"

checkRequirement(){
if [[ $freemem -lt 100 ]]
then
echo "low on memory"
exit 1
elif [[ $freespace -gt 95 ]]
then
echo  "low on storage"
exit 1
elif [[ $version != " CentOS Linux 7 (Core)" ]]
then
echo "centos is not 7"
exit 1
fi
}


checkRequirement


dockerInstall(){
yum check-update &> /tmp/file.log
yum install -y yum-utils device-mapper-persistent-data lvm2 &>> /tmp/file.log
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &>> /tmp/file.log
yum install docker-ce-19.03.13-3.el7 docker-ce-cli-19.03.13-3.el7 containerd.io -y &>> /tmp/file.log

systemctl enable docker
systemctl start docker
}

dockerRemove(){
systemctl stop docker
systemctl enable docker
yum remove -y yum-utils device-mapper-persistent-data lvm2 &>> /tmp/file.log
yum remove docker-ce-19.03.13-3.el7 docker-ce-cli-19.03.13-3.el7 containerd.io -y &>> /tmp/file.log
echo "removing docker"
}


kubeInstall(){
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF


yum install kubeadm-1.19.4 kubectl-1.19.4 kubelet-1.19.4 -y &> /tmp/file.log
systemctl enable kubelet
systemctl start kubelet
hostnamectl set-hostname $hostname
echo $ip4 $hostname >> /etc/hosts

yum install firewalld
systemctl enable firewalld


firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=10251/tcp
firewall-cmd --permanent --add-port=10252/tcp
firewall-cmd --permanent --add-port=10255/tcp
firewall-cmd --reload



cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system




setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
sed -i '/swap/d' /etc/fstab
rwapoff -a

kubeadm init

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config


kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml



}
dockerInstall
kubeInstall
