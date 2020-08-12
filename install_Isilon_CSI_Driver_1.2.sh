#!/bin/bash
#Author: Anjan Dave
#Version: 1.1
printf "\n\tThis interactive script installs the CSI Driver 1.2. Try to run it once only as there's not a ton of logic built-in to check for already installed components if you re-run the script.\n"
printf "\nPlease, do NOT use this to install a PRODUCTION environment, this is just to play with the CSI driver!!!!! \n"
printf "\nNOTE: We are only working with a k8s cluster with just master node, no workers \n"
printf "\nNOTE: We are going to install the CSI driver files in /root and as root\n"
printf "\nNOTE: Kubernetes 1.16 is expected, if you used my other scripts in the repo to install docker & kubernetes, you should be fine \n\n"
sleep 10 


function main
{

#First let's make sure we get the IP address of this host right, as there can be multiple IPs due to various virtual interfaces
echo ""
ifconfig -a | grep inet | grep -v inet6 | grep -v 127.0
printf "Which of the above is the IP address of this host that you used to connect to it? type the IP  here: \n"
read newip
printf "We'll use this IP you provided for one of the kubernetes config file, if you made a mistake, type ctrl+c: $newip \n\n"
sleep 4 

#Install GIT if not already done 
printf "Let's first check if git is installed, and if not we'll install it \n\n"
git version
sleep 3
if [ $? -eq 0 ]
then
	printf "Looks like git is installed, moving on\n\n"
else
	printf "Installing git...make sure you type yes if asked by yum\n"
	yum install git
fi

#GIT Clone the CSI Driver - here we could fail in future if the driver files get updated
printf "\nNext, we clone the CSI Driver repo, if it doesn't exist, using git in /root. It will create a csi-install dir... \n"
sleep 4
cd /root
if [ -d "/root/csi-isilon" ]
then
	printf "\nThe csi-isilon directory exists already. If you want to install the driver using this script, rename that directory first\n"
	sleep 3
else
	git clone https://github.com/dell/csi-isilon.git
	printf "\nCheck below if you see the csi-isilon directory listed\n"
	ls /root
fi

#For below, I have copied the current 1.0 CSI driver configuration files (already configured files) and put them on github
#But keep in mind, certain files are path dependent based on how/where docker and k8s are installed, again if you followed my scripts to install#docker and kubernetes you should be fine

printf "Next, we will download configuration files from github. This avoids the step wherein you'd have to edit several files, which is error-prone process.\n\n"
printf "NOTE: The path for each file is based on where docker and kubernetes components are installed. If you intalled docker & k8s using my scripts you're fine. Otherwise, if those paths are different for you, then hit ctrl+c NOW as we could fail. The paths for files we will work on are: \n"
printf "/var/lib/kubelet/config.yaml \n"
printf "/etc/kubernetes/manifests/kube-apiserver.yaml \n"
printf "/etc/kubernetes/manifests/kube-controller-manager.yaml \n"
printf "/etc/kubernetes/manifests/kube-scheduler.yaml \n"
printf "/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf \n"
printf "/etc/systemd/system/multi-user.target.wants/docker.service \n"
sleep 10

cd /root
if [ -d "/root/isilon-csi-script" ]
then
	printf "\nLooks like you already have downloaded the isilon-csi-script repo in /root/isilon-csi-script directory, if you want to get it again, hit ctrl+c now, and go back and rename it first\n"
	sleep 6
else
	git clone https://github.com/acd13/isilon-csi-script-1.2.git
	printf "\nCheck below if /root has the csi-files dir\n"
	ls /root
	sleep 5
fi

#We bkp existing files, no harm in repeating this step
printf "\nNext, we backup the existing files in /root/csi-bkp-files \n"
mydate=`date +%F`
/bin/mkdir -p /root/csi-bkp-files
cp /var/lib/kubelet/config.yaml /root/csi-bkp-files/config.yaml.$mydate
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/csi-bkp-files/kube-apiserver.yaml.$mydate
cp /etc/kubernetes/manifests/kube-controller-manager.yaml /root/csi-bkp-files/kube-controller-manager.yaml.$mydate
cp /etc/kubernetes/manifests/kube-scheduler.yaml /root/csi-bkp-files/kube-scheduler.yaml.$mydate
cp /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf /root/csi-bkp-files/10-kubeadm.conf.$mydate
cp /etc/systemd/system/multi-user.target.wants/docker.service /root/csi-bkp-files/docker.service.$mydate
cp /etc/docker/daemon.json /root/csi-bkp-files/daemon.json.$mydate
printf "\nBackup of configuration files done, check below listing: \n"
ls -l /root/csi-bkp-files
sleep 4

printf "Now copying files from isilon-csi-script to various paths \n"
cp /root/isilon-csi-script/csi-files/config.yaml /var/lib/kubelet/
cp /root/isilon-csi-script/csi-files/kube-* /etc/kubernetes/manifests/
cp /root/isilon-csi-script/csi-files/10-kubeadm.conf /usr/lib/systemd/system/kubelet.service.d/
cp /root/isilon-csi-script/csi-files/docker.service /etc/systemd/system/multi-user.target.wants/
printf "\nDone."

#From above files, we only modify the kube-apiserver.yaml for the IP so no harm in repeating the step
printf "\n Changing the IP address field in /etc/kubernetes/manifests/kube-apiserver.yaml file \n"
printf "Below is the current IP which we will change \n"
more /etc/kubernetes/manifests/kube-apiserver.yaml | grep advertise-address 
sleep 5
ipaddress=`more /etc/kubernetes/manifests/kube-apiserver.yaml | grep advertise-address | sed -r 's/[^0-9.]+//'`
sed -i -e 's/'$ipaddress'\b/'$newip'/' /etc/kubernetes/manifests/kube-apiserver.yaml
printf "Did we change the IP properly? See below otherwise please change it manually for the kube-apiserver.yaml file \n"
more /etc/kubernetes/manifests/kube-apiserver.yaml | grep advertise-address
sleep 10

#Adding /etc/docker/daemon.json file
rm -rf /etc/docker/daemon.json
cat <<EOF > /etc/docker/daemon.json
{
"insecure-registries" : ["artifactory-sio.isus.emc.com:8129"]
}
EOF

#No harm in restarting below items repeatedly, it just needs more sleep time afterwards to wait for PODs to come on
printf "\nNow restarting docker and kubernetes...waiting for 20 seconds to let everything settle\n\n"
systemctl daemon-reload
systemctl restart docker
systemctl restart kubelet
sleep 15
echo ""

ps -aux | grep kube-api | grep CSI
printf "\nDo you see the CSINodeInfo=true, etc fields in above output at the bottom?? \n"
printf "If not, press ctrl+c to exit, something is not right! \n\n"
sleep 15
printf "If above output is right, do you see below all PODs in running state? If not, ctrl+c, something is not right! \n"
kubectl get pods -A
sleep 10

#Below, we install the tiller POD
printf "\nPLEASE DISCONNECT FROM THE VPN FOR THIS STEP OTHERWISE IT MAY NOT WORK \n"
printf "Did you disconnect from VPN? yes/no: \n"
read ansvpn
if [ $ansvpn = yes ]
then
	printf "\nNext, we install the helm and tiller packages which will create a tiller pod in your k8s cluster \n"
	printf "\nLet's check if you already did this...\n\n"
	kubectl get pods -A | grep tiller
	if [ $? -eq 0 ]
 	then
		printf "\nLooks like you've already got the tiller pod running, skipping this step"
		sleep 8
	else
		printf "\nDownloading tiller package now...\n"
		sleep 10
		cd /root
		curl https://raw.githubusercontent.com/helm/helm/master/scripts/get > get_helm.sh
		chmod 700 get_helm.sh
		printf "\nRunning helm installer we just downloaded...\n"
		sleep 5
		./get_helm.sh
		sleep 5
		printf "\nNow initializing helm using helm init...\n"
		helm init
	fi
else
exit 0
fi

} #End of main function

#Call the main function defined above
main



function tillerstuff
{

#Below, we check for a Taint. Because we have a single-node cluster that just has the master node, it will end up with a taint, and we need to remove it. Production k8s cluster may want this taint on the master node

printf "\nLet's see if the tiller POD is in Pending state, just in case \n"
tillerstatus=`kubectl get pods -A | grep tiller | awk '{print $4}'`
if [ $tillerstatus == Pending ]
then
	printf "Tiller POD is in pending, state... \n\n"
	kubectl describe pod `kubectl get pods -A | grep tiller | awk '{print $2}'` -n kube-system | grep taints
  	if [ $? -eq 0 ]
  	then
  		printf "\nLooks like it's Pending because of a taint on the only node (master) we have...will try to remove taint \n"
  		kubectl describe pod `kubectl get pods -A | grep tiller | awk '{print $2}'` -n kube-system | grep taints
  		kubectl taint nodes `kubectl get nodes | grep v1 | awk '{print $1}'` node-role.kubernetes.io/master-
  		printf "\nTaint removed... \n"
  		sleep 10
  		kubectl get pods -A | grep tiller
  	fi
else
	printf "\nTiller pod is not in Pending state, assuming it's Running, see below output \n"
	kubectl get pods -A | grep tiller
fi

#We can continue ONLY if ALL pods are in running state, so check for that
echo "-----------------------------"
echo ""
kubectl get pods -A
printf "\nAre ALL pods in Running state? \n"
printf "We will continue ONLY if all pods are running - yes/no: \n\n"
read podans
if [ $podans = no ]
then
exit 0
fi

#Check if the service account for tiller already exists
kubectl get serviceaccounts -A | grep tiller
if [ $? -eq 0 ]
then
	printf "In above, Tiller service account exists, skipping this step \n"
	:
else
	printf "\nNext step is to create tiller service account. For that, we invoke the rbac-config.yaml file from /root/isilon-csi-script/csi-files to setup Tiller ServiceAccount in k8s\n"
	kubectl create -f /root/isilon-csi-script/csi-files/rbac-config.yaml
	sleep 8
	printf "\nNext, we need to apply the tiller service account to tiller pod \n"
	helm init --upgrade --service-account tiller
fi

printf "\nNext, we create the isilon & the test namespace in the k8s cluster \n"
kubectl create namespace isilon
kubectl create namespace test
sleep 4

} #End of function tillerstuff

#Call the tillerstuff function
tillerstuff




#Below function is to handle the secret.yaml file mainly
function secretstuff
{
printf "\n For the next step, following should be ready
1. Isilon cluster and it's credentials (root or another account with appropriate privs as per CSI Driver Guide
2. Management IP of the cluster
3. A path such as /ifs/blah/csi-volumes already created on cluster
\n"

printf "If you're ready with above things, type yes/no: \n\n"
read ready
if [ $ready = yes ]
then
	:
else
	exit 0
fi

kubectl get secret -n isilon | grep isilon-creds
if [ $? -eq 0 ]
then
	printf "Looks like the secret is already created, skipping... \n"
	:
else
	printf "Let's create the secret.yaml file first \n"
	sleep 4
	printf "Enter Isilon username for CSI Driver (that has all the privs): \n"
	read isiuser
	printf "Enter the password for this account: \n"
	read isipasswd
	myisiuser=`echo -n "$isiuser" | base64`
	myisipasswd=`echo -n "$isipasswd" | base64`

cat <<EOF > /root/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: isilon-creds
  namespace: isilon
type: Opaque
data:
  # set username to the base64 encoded username
  username: userid
  # set password to the base64 encoded password
  password: passid
EOF

	sed -i 's/userid/'$myisiuser'/' /root/secret.yaml
	sed -i 's/passid/'$myisipasswd'/' /root/secret.yaml
	printf "\n Below is the secret.yaml file, will invoke it in k8s now \n"
	cat /root/secret.yaml
	echo ""
	kubectl create -f /root/secret.yaml
	kubectl get secret -n isilon | grep isilon-creds
fi

#Last step - verify the kubernetes script that comes with the CSI Driver files we cloned in the beginning of script
#No problem in running the verify.kubernetes every time we're called upon, nothing changes
printf "\nModifying permissions to executable on /root/csi-isilon/helm/verify.kubernetes \n"
chmod 755 /root/csi-isilon/helm/verify.kubernetes

echo "----------------------------------------------------------------------"
printf "\nNext, we run the verify.kubernetes script
Make sure you supply the root password of THIS host, it will ask twice
You must get a successful verification message prior to installing the CSI Driver PODs \n"
echo "----------------------------------------------------------------------"
echo ""
sh /root/csi-isilon/helm/verify.kubernetes

printf "At this time, everything is ready. You should have the Isilon's management IP and a path for CSI volume ready \n\n"

} #End of secretstuff function

#Call the secretstuff function defined above
secretstuff



#Now copying values.yaml to myvalues.yaml
#Below will simply fail if you run this script more than once due to -n argument to cp
printf "\nCopying /root/csi-isilon/helm/csi-isilon/values.yaml to /root/csi-isilon/helm/myvalues.yaml \n"
cp -n /root/csi-isilon/helm/csi-isilon/values.yaml /root/csi-isilon/helm/myvalues.yaml
printf "\nDone.\n\n"

printf "Existing IP and Path parameters in the /root/csi-isilon/helm/myvalues.yaml and volumesnapshotclas
s.yaml files are as shown below\n\n"
cat /root/csi-isilon/helm/myvalues.yaml | egrep "isiIP:|isiPath"
echo ""
cat /root/csi-isilon/helm/volumesnapshotclass.yaml | grep IsiPath

printf "\n\nDo you want to modify myvalues.yaml and volumesnapshotclass.yaml files. Asking because just in case you are running this script again? yes/no: \n"
read modifyans
if [ $modifyans = yes ]
then
	printf "Enter the management IP of the Isilon cluster: \n"
	read mgmtip
	printf "Enter the Isilon path (e.g. /ifs/cluster/csi) for CSI driver to create it's volumes: \n"
	read isilonpath
	sleep 4
	printf "Now changing the myvalues.yaml file for the IP and the path you supplied \n\n" 
	sed -i 's/isiIP: 1.1.1.1/isiIP: '$mgmtip'/' /root/csi-isilon/helm/myvalues.yaml
	sed -i 's#/ifs/data/csi#'$isilonpath'#' /root/csi-isilon/helm/myvalues.yaml
	printf "Now changing volumesnapshotclass.yaml file for the path \n"
	sed -i 's#/ifs/data/csi#'$isilonpath'#' /root/csi-isilon/helm/volumesnapshotclass.yaml
	printf "\nCheck below if i changed the IP and path correctly, else modify the /root/csi-isilon/helm/myvalues.yaml and volumesnapshotclass.yaml files by hand \n"
	cat /root/csi-isilon/helm/myvalues.yaml | egrep "isiIP:|isiPath"
	echo ""
	cat /root/csi-isilon/helm/volumesnapshotclass.yaml | grep IsiPath
fi


#Last step - install the CSI Driver!!!
printf "\nNext, and last step of this script is to run the install.isilon script that will install the 2 CSI Driver related pods \n"
printf "This step can take about a minute or two and it will run the verify.kubernetes script again, so supply the credentials for this host, twice\n"
sleep 8
printf "\nContinue? Type no if you have the driver running, obviously...yes/no: "
read csicontinue
if [ $csicontinue = yes ]
then
	cd /root/csi-isilon/helm
	sh install.isilon
else
exit 0
fi

echo ""
kubectl get pods -A
printf "\nIf you don't see the two PODS related to CSI Driver in isilon namespace in Running state, give it a couple of minutes \n"

#Take care of volumesnapshotclass if it failed during driver install...let's install it anyway, if there's no POD in non-Running state
printf "\nInstalling volumesnapshotclass, in case if it failed as the last step of driver install. \n\n"
kubectl get pods -A | grep -v Running | grep -v STATUS
if [ $? -eq 1 ]
then
	echo "installing volumesnapshotclass"; kubectl create -f volumesnapshotclass.yaml
	echo "VolumeSnapshotClasses:"
	kubectl get volumesnapshotclass
fi

echo ""
kubectl get pods -A
printf "\nIf you don't see the two PODS related to CSI Driver in isilon namespace in Running state, give it a couple of minutes \n"
printf "\nIf you DO see the two PODS in isilon name space in Running status, this completes the installation \n\n"
printf "Goodbye!\n"
