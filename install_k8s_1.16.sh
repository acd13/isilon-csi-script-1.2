#!/bin/bash
#Auther: Anjan Dave
#Version: 1.1
printf "\n\tThis script installs kubernetes v1.16.12 on a Linux 7.x host. Make sure the CentOS install is not of a -minimum- kind, install the GNOME Desktop version and include developer, admin tools, etc"
printf "\nWe assume that latest version of Docker is installed on this host already\n"
printf "\nThis script makes a reasonable effort to check fo things already installed if you have to run it over and over again\n"
printf "\n There are no arguments to this script\n"
sleep 3

#Start of script
#Check that we have more than 1 CPUs otherwise cannot proceed
nocpus=`lscpu | grep CPU"(s)": | grep -v NUMA | awk '{print $2}'`
if [ $nocpus -eq 1 ]
then
printf "You only have 1 CPU defined which is not enough, increase to at least 2 and then run the script again\n"
exit 0
fi

echo ""
echo "Let's disable Swap first, using swapoff -a and edit the /etc/fstab file..."
swapoff -a
printf "Did a swapoff -a. Next let's edit the /etc/fstab to comment out the swap line...\n"

cat /etc/fstab | grep swap | grep "#"
if [ $? -eq 0 ]
then
echo "Looks like /etc/fstab line for swap is already commented out, see below"
cat /etc/fstab | grep swap
else
echo "We need to comment out the swap line in /etc/fstab"
sed -i 's|\/dev\/mapper\/centos_k8s--faction-swap|#\/dev\/mapper\/centos_k8s--faction-swap|g' /etc/fstab
echo "Check below line to make sure my sed did it's job, i.e., put a comment on the swap line:"
cat /etc/fstab | grep swap
fi
echo ""
sleep 3

echo "Let's make sure docker is running specifically hello-world container"
dockerstatus=`docker ps -a | grep world | awk '{print $2'}`
if [ $dockerstatus = hello-world ]
then
echo $dockerstatus
printf "looks fine\n"
fi

repofile=/etc/yum.repos.d/kubernetes.repo
if [ -f "$repofile" ]
then
echo ""
echo "Looks like the kubernetes.repo file already exists as below:"
cat /etc/yum.repos.d/kubernetes.repo
fi

printf "\nProceed next to creating k8s repo config file? yes/no: "
read ans
if [ $ans = yes ]
then
echo "deleting existing file and recreating"
rm /etc/yum.repos.d/kubernetes.repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF
echo "Done, check below contents of /etc/yum.repos.d/kubernetes.repo..."
cat /etc/yum.repos.d/kubernetes.repo
fi

sleep 3

printf "\nNext, we change linux security settings so it's permissive"
setenforce 0
cat /etc/selinux/config | grep SELINUX=enforcing
if [ $? -eq 0 ]
then
echo "SELINUX needs to be set to permissive instead of enforcing, changing it..."
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
echo "check below"
cat /etc/selinux/config | grep SELINUX=permissive
else
printf "\nDone, check below\n"
cat /etc/selinux/config | grep SELINUX=permissive
fi

printf "\nNext, let's stop firewalld service and disable it"
service firewalld stop
systemctl disable firewalld
sleep 4


printf "\nCheck if below kubernetes version already installed is fine, if it is then type no\n"
yum list installed | grep kube
printf "\nFor next step we install kubernetes 1.16.12. If we have to, PLEASE MAKE SURE YOURE DISCONNECTED FROM VPN"
echo "Proceed with kubernetes package installation? yes/no: "
read ans2
if [ $ans2 = yes ]
then
printf "\nNow we install the k8s 1.16.12 packages..."
yum install -y kubelet-1.16.12-0 kubeadm-1.16.12-0 kubectl-1.16.12-0 --disableexcludes=kubernetes
fi

printf "\nEnable kubelete service with command: systemctl enable --now kubelet..."
systemctl enable --now kubelet

printf "\nSome users on RHEL-CentOS 7 have reported issues with traffic being routed incorrectly due to iptables being bypassed. You should ensure net.bridge.bridge-nf-call-iptables is set to 1 in your sysctl config"
printf "\nExisting file is as below, no change needed if net.bridge values are already set to 1\n"
cat /etc/sysctl.d/k8s.conf
echo ""

echo "Based on above output, proceed with modifying k8s.conf? yes/no: "
read ans3
if [ $ans3 = yes ]
then
rm -rf /etc/sysctl.d/k8s.conf
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
fi
printf "\nCheck if below contents look good\n"
cat /etc/sysctl.d/k8s.conf

printf "\nDoing a systemctl --system now to modify kernel parameters..."
sysctl --system

cat <<EOF > /proc/sys/net/ipv4/ip_forward
1
EOF


printf "\nIn below output of lsmod, make sure you see br_netfilter module loaded \n"
lsmod | grep br_netfilter

printf "\n Next step is to initialize the kubernetes cluster using kubeadmin init. Do this ONLY if you've not already done it prior, otherwise say no\n"
printf "Initialize the kubernetes cluster now? yes/no: "
read ans4
if [ $ans4 = yes ]
then
kubeadm init --pod-network-cidr=10.244.0.0/16
printf "\nIf in above output, you did not see successful initialization, then stop here and troubleshoot!\n"
fi

printf "\nCopying admin.conf, in .kube directory...\n"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
printf "done.\n"

cat /root/.bash_profile | grep KUBECONFIG
if [ $? = 1 ]
then
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.bash_profile
fi

printf "\nCheck kubectl get nodes output below\n"
kubectl get nodes

sleep 3
printf "\nCheck if we have a whole bunch of kubernetes containers running inside docker, if you don't see that then something went wrong\n"
docker ps -a

sleep 5

printf "\nNow we apply the Weave-net network to the cluster\n"
kubectl get pods -A | grep weave-net
if [ $? -eq 0 ]
then
printf "\nLooks like you've already installed weave-net in prior step, installing it again may not help\n"
fi
printf "Proceed with weave-net? yes/no: "
read ans5
if [ $ans5 = yes ]
then
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
fi

printf "\n\t At this point, your k8s master node and the pods should be fine. Check below outputs, if the master node is not in Ready status or if any of the PODS are not in Running status, then give it few mins otherwise it needs to be troubleshooted\n"
kubectl get nodes
echo ""
kubectl get pods -A

printf "\nAll done. Goodbye!"
