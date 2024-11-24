---
# Documentation: https://docs.hugoblox.com/managing-content/

title: "Kubernetes"
subtitle: "k8s学习笔记"
summary: "在b站学习up主叩丁狼的k8s教程视频 https://www.bilibili.com/video/BV1MT411x7GH 记录的学习笔记"
authors: []
tags: []
categories: ["笔记", "k8s"]
date: 2023-07-24T16:03:10+08:00
lastmod: 2023-07-24T16:03:10+08:00
featured: false
draft: false

# Featured image
# To use, add an image named `featured.jpg/png` to your page's folder.
# Focal points: Smart, Center, TopLeft, Top, TopRight, Left, Right, BottomLeft, Bottom, BottomRight.
image:
  caption: ""
  focal_point: ""
  preview_only: false

# Projects (optional).
#   Associate this post with one or more of your projects.
#   Simply enter your project's folder or file name without extension.
#   E.g. `projects = ["internal-project"]` references `content/project/deep-learning/index.md`.
#   Otherwise, set `projects = []`.
projects: []
---



## kubernetes(k8s)

### 一.搭建k8s集群

在CentOS7下搭建

##### 1.修改网络

```shell
vim /etc/sysconfig/network-scripts/ifcfg-ens33
```

默认配置

```shell
# 备份
cp /etc/sysconfig/network-scripts/ifcfg-ens33{,.bak}
```

```sh
TYPE="Ethernet"
PROXY_METHOD="none"
BROWSER_ONLY="no"
BOOTPROTO="dhcp"
DEFROUTE="yes"
IPV4_FAILURE_FATAL="no"
IPV6INIT="yes"
IPV6_AUTOCONF="yes"
IPV6_DEFROUTE="yes"
IPV6_FAILURE_FATAL="no"
IPV6_ADDR_GEN_MODE="stable-privacy"
NAME="ens33"
UUID="38511cb8-8b7d-41fa-bc23-772a52280195"
DEVICE="ens33"
ONBOOT="yes"
```

写入一下内容

```sh
TYPE="Ethernet"
PROXY_METHOD="none"
BROWSER_ONLY="no"
BOOTPROTO="static"
DEFROUTE="yes"
IPV4_FAILURE_FATAL="no"
IPV6INIT="yes"
IPV6_AUTOCONF="yes"
IPV6_DEFROUTE="yes"
IPV6_FAILURE_FATAL="no"
IPV6_ADDR_GEN_MODE="stable-privacy"
NAME="ens33"
UUID="38511cb8-8b7d-41fa-bc23-772a52280195"
DEVICE="ens33"
ONBOOT="yes"
IPADDR="192.168.28.120"
PREFIX="24"
GATEWAY="192.168.28.2"
NETMASK="255.255.255.0"
BROADCAST="192.168.28.255"
DNS1="192.168.28.2"
IPV6_PRIVACY="no"
```

```shell
# 重启网络
systemctl restart network
service network restart
```

```shell
# 修改hostname 
hostnamectl set-hostname k8smaster

# 修改主机名
vim /etc/hostname

# 修改host
vim /etc/hosts
```

##### 2.配置系统

**因为k8s 和 docker 这俩憨皮自己搞防火墙规则，和你的防火墙规则冲突。**

**至在计算集群（请注意计算集群这四个字的含义，这种集群主要运行一些生存周期短暂的计算应用，申请大量内存-动用大量CPU-完成计算-输出结果-退出，而不是运行诸如mysql之类的服务型程序）中，我们通常希望OOM的时候直接杀掉进程，向运维或者作业提交者报错提示，并且执行故障转移，把进程在其他节点上重启起来。而不是用swap续命，导致节点hang住，集群性能大幅下降，并且运维还得不到报错提示。更可怕的是有一些集群的swap位于机械硬盘阵列上，大量动用swap基本可以等同于死机，你甚至连root都登录不上，不用提杀掉问题进程了。往往结局就是硬重启。**

**节点hang住是非常恶劣的情况，往往发现问题的时候，已经造成了大量损失。而程序出错可以自动重试，重试还OOM说明出现了预料之外的情况（比如程序bug或是预料之外的输入、输入文件大小远超预期等问题），这种时候就应该放弃这个作业等待人员处理，而不是不停地尝试着执行它们，从而导致后面的其他作业全部完蛋。**

**所以计算集群通常都是关闭swap的，除非你十分明确swap可以给你的应用带来收益。**

**计算集群和诸如执行mysql的集群有一个根本不同就是计算集群不在意单个进程、单个作业的失败（由于面向的用户很宽泛，这些作业所执行的程序很可能未经严格的测试，它们客观上出问题的几率远高于mysql等成熟的程序），但是绝对不接受hang住引起整个集群无法处理任何作业，这是非常严重的事故。**

**关闭swap的含义其实就是OOM了就赶紧滚蛋，让正常的程序进来继续执行，OOM的程序让用户去处理**。

```shell
# 关闭防火墙
systemctl stop firewalld
systemctl disable firewalld

# 关于selinux的原因（关闭selinux以允许容器访问宿主机的文件系统）
# 关闭selinux
sed -i 's/enforcing/disabled/' /etc/selinux/config  # 永久
setenforce 0  # 临时

# 关闭swap
swapoff -a  # 临时
sed -ri 's/.*swap.*/#&/' /etc/fstab    # 永久

# 关闭完swap后，一定要重启一下虚拟机！！！
# 根据规划设置主机名
hostnamectl set-hostname <hostname>

# 在master添加hosts
cat >> /etc/hosts << EOF
192.168.28.120 k8s-master
192.168.28.121 k8s-node1
192.168.28.122 k8s-node2
EOF

# 关于防火墙的原因（nftables后端兼容性问题，产生重复的防火墙规则）
# 将桥接的IPv4流量传递到iptables的链
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system  # 生效


# 时间同步
yum install ntpdate -y
ntpdate time.windows.com
```



##### 3.docker安装

**确定版本**

```shell
# 需要安装与Kubernetes兼容的docker版本
https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.23.md
https://github.com/kubernetes/kubernetes/blob/v1.23.6/build/dependencies.yaml

  # Docker
  - name: "docker"
    version: 20.10
    refPaths:
    - path: vendor/k8s.io/system-validators/validators/docker_validator.go
      match: latestValidatedDockerVersion
      
# containerd也需要和Docker兼容

https://docs.docker.com/engine/release-notes/
https://github.com/moby/moby/blob/v20.10.7/vendor.conf
```

**所以这里Docker安装20.10.7版本，containerd安装1.4.6版本**

```shell
# step 1: 安装必要的一些系统工具
sudo yum install -y yum-utils device-mapper-persistent-data lvm2

sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

# PS:如果出现如下错误信息
Loaded plugins: fastestmirror
adding repo from: https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
grabbing file https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo to /etc/yum.repos.d/docker-ce.repo
Could not fetch/save url https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo to file /etc/yum.repos.d/docker-ce.repo: [Errno 14] curl#60 - "Peer's Certificate issuer is not recognized."
# 编辑 /etc/yum.conf 文件, 在 [main] 下面添加 sslverify=0 参数
vi /etc/yum.conf
# 配置如下----------------------
[main]
sslverify=0
# -----------------------------


# Step 3: 更新并安装Docker-CE
sudo yum makecache fast
yum -y install docker-ce-20.10.7 docker-ce-cli-20.10.7 containerd.io-1.4.6  docker-ce-rootless-extras-20.10.7 docker-scan-plugin-20.10.7

# 安装指定版本的Docker-CE:
# Step 1: 查找Docker-CE的版本:
# yum list docker-ce.x86_64 --showduplicates | sort -r
#   Loading mirror speeds from cached hostfile
#   Loaded plugins: branch, fastestmirror, langpacks
#   docker-ce.x86_64            17.03.1.ce-1.el7.centos            docker-ce-stable
#   docker-ce.x86_64            17.03.1.ce-1.el7.centos            @docker-ce-stable
#   docker-ce.x86_64            17.03.0.ce-1.el7.centos            docker-ce-stable
#   Available Packages
# Step2: 安装指定版本的Docker-CE: (VERSION例如上面的17.03.0.ce.1-1.el7.centos)
# sudo yum -y install docker-ce-[VERSION]



# Step 4: 开启Docker服务
sudo service docker start

# 安装完成校验
docker version

# docker开机自启动
systemctl enable docker

# Docker加速
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://55fwm9g2.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

移除docker

```shell
# 查看是否安装过docker
rpm -qa | grep docker
# 移除
yum -y remove docker-ce && \
yum -y remove docker-compose-plugin docker-buildx-plugin docker-ce-cli docker-scan-plugin

sudo yum remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine
```



##### 4.添加阿里云yum源

```sh
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0

gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
```

##### 5.安装 kubeadm、kubelet、kubectl

```shell
yum install -y kubelet-1.23.6 kubeadm-1.23.6 kubectl-1.23.6

# 移除
yum remove -y kubelet-1.23.6 kubeadm-1.23.6 kubectl-1.23.6


# 在安装时出现yum仓库错误可以使用 清除缓存
yum cliean all


systemctl enable kubelet

# 配置关闭 Docker 的 cgroups，修改 /etc/docker/daemon.json，加入以下内容
"exec-opts": ["native.cgroupdriver=systemd"]

# 重启 docker
systemctl daemon-reload && \
systemctl restart docker
```

##### debain安装

```sh
# 查看是否有虚拟内存
free -m

# 当前状态关闭虚拟内存
swapoff -a

# 关闭虚拟内存 在开机挂载中关闭挂载 添加注释
sed -ri 's/.*swap.*/#&/' /etc/fstab



# linux内核参数配置
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

# 时间同步
ntpdate ntp.aliyun.com
echo "203.107.6.88 root ntpdate ntp.aliyun.com" >> /etc/crontab




# 添加docker配置
vim /etc/docker/daemon.json 
# 添加 "exec-opts": ["native.cgroupdriver=systemd"]

# 重启docker
systemctl daemon-reload
systemctl restart docker

# 更新下载软件
apt-get update && apt-get install -y apt-transport-https curl

# 
vim /etc/apt/sources.list

# 添加软件镜像源配置
deb https://mirrors.aliyun.com/kubernetes/  kubernetes-xenial main
deb http://apt.kubernetes.io/ kubernetes-xenial main
 

curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | gpg --dearmour -o /etc/apt/trusted.gpg.d/caliyum.gpg


sudo apt install gnupg gnupg2 curl software-properties-common -y
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/cgoogle.gpg
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"

curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | gpg --dearmour -o /etc/apt/trusted.gpg.d/caliyum.gpg

# 安装最新版本，不要安装最新版本，containerd版本低不支持，需要升级到1.6版本，使用下面的版本
apt-get install -y kubelet kubeadm kubectl  
apt-mark hold kubelet kubeadm kubectl  #设置不随系统更新而更新

# 安装指定版本
apt-get install -y kubelet=1.23.6-00 kubeadm=1.23.6-00 kubectl=1.23.6-00



# 在 Master 节点下执行
kubeadm init \
      --apiserver-advertise-address=192.168.10.2 \
      --image-repository registry.aliyuncs.com/google_containers \
      --kubernetes-version v1.23.6 \
      --service-cidr=10.96.0.0/12 \
      --pod-network-cidr=10.244.0.0/16


# 去除主节点污点
# 实现单节点使用
kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl taint no  debian node-role.kubernetes.io/master-

```



##### 6.部署kubernetes master

```shell
# 在 Master 节点下执行
kubeadm init \
      --apiserver-advertise-address=192.168.28.120 \
      --image-repository registry.aliyuncs.com/google_containers \
      --kubernetes-version v1.23.6 \
      --service-cidr=10.96.0.0/12 \
      --pod-network-cidr=10.244.0.0/16

# 安装成功后，复制如下配置并执行
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 查看节点
kubectl get nodes


# 出现问题  删除生成文件
# 重置配置
rm -rf /etc/kubernetes/*
kubeadm reset
# 查找端口占用 lsof -i:17594
# 干掉进程 kill -9 17594

# Master节点删除工作目录，并重置kubeadm
rm -rf /etc/kubernetes/*
rm -rf ~/.kube/*
rm -rf /var/lib/etcd/*
kubeadm reset -f

# 当程序未启动时
journactl -xefu kubele
```

##### 7.加入kubernetes node

```shell
分别在 k8s-node1 和 k8s-node2 执行

# 下方命令可以在 k8s master 控制台初始化成功后复制 join 命令

kubeadm join 192.168.28.120:6443 --token icnp9o.2zqc589ba6sf3bad --discovery-token-ca-cert-hash sha256:0f5c6e5b70355d51e63d058b3330b826a566f6bd022045b1db90ccfba3bbb7be


# 如果初始化的 token 不小心清空了，可以通过如下命令获取或者重新申请
# 如果 token 已经过期，就重新申请
kubeadm token create

# token 没有过期可以通过如下命令获取
kubeadm token list

# 获取 --discovery-token-ca-cert-hash 值，得到值后需要在前面拼接上 sha256:
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | \
openssl dgst -sha256 -hex | sed 's/^.* //'
```

##### 8.部署CNI网络插件

```shell
# 查看组件状态
kubectl get cs

# 查看pods       		指定命名空间
kubectl get pods -n kubu-system


# 在 master 节点上执行
# 下载 calico 配置文件，可能会网络超时
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml -O

# 修改 calico.yaml 文件中的 CALICO_IPV4POOL_CIDR 配置，修改为与初始化的 cidr 相同

# 修改 IP_AUTODETECTION_METHOD 下的网卡名称

# 删除镜像 docker.io/ 前缀，避免下载过慢导致失败
sed -i 's#docker.io/##g' calico.yaml

# 构建
kubectl apply -f calico.yaml

# 查看prod情况
kubctl get po -n kube-system

# 指定查看某个的状态
kubectl describe po calico-kube-controllers-6fbdddcf6b-4g6hj -n kube-system
```

9.测试kubernetes 集群

```shell
# 创建部署
kubectl create deployment nginx --image=nginx

# 暴露端口
kubectl expose deployment nginx --port=80 --type=NodePort

# 查看 pod 以及服务信息
kubectl get pod,svc
```



### 二.Pod

##### 1.任意节点使用kubctl

```shell
# 1. 将 master 节点中 /etc/kubernetes/admin.conf 拷贝到需要运行的服务器的 /etc/kubernetes 目录中
scp /etc/kubernetes/admin.conf root@k8s-node1:/etc/kubernetes

# 2. 在对应的服务器上配置环境变量
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bash_profile
source ~/.bash_profile

```

##### 2.kubectl使用

```shell
kubectl [command] [TYPE] [NAME1,NAME2...] [flags]
	command: 		对一个或多个资源的操作 
		create		创建
		get			获取
		describe	描述
		delete		删除
	TYPE:			指定资源类型(不区分大小写,可以指定(单数,复数,缩写)一样的)
		po			pod, pods 资源
		deploy		deployment,deployments资源
		svc			service,services资源
		ns			namespace,namespaces 资源
		no			node,nodes资源
		sts			statefulset
		pvc			PersistentVolumeClaim 存储资源
	NAME:			指定资源名称(区分大小写),如果省略名称显示所有资源的详细信息,可以多个名称一起写
	flags:			指定可选参数
		-s			--server 指定服务器地址和端口
		-o			wide 纯文本格式输出信息, json输出json格式,yaml输出yaml格式,name输出资源名称
		
	
# 资源类型与别名
pods po
deployments deploy
services svc
namespace ns
nodes no





# 获取namespace
kubectl get namespace
kubectl get ns


# 获取pods
kubectl get po
kubectl get pods

# 获取deployments
kubectl get deployments
kubectl get deploy

#NAME    READY   UP-TO-DATE   AVAILABLE   AGE
#nginx   1/1     1            1           6d18h

kubectl get deploy nginx
#NAME    READY   UP-TO-DATE   AVAILABLE   AGE
#nginx   1/1     1            1           6d18


# 获取services
kubectl get services
kubectl get svc


# scale资源


# 查看默认命名空间
kubectl get po -n kube-system

# 编辑配置文件
kubectl edit po -n kube-system coredns-6d8c4cb4d-7jzms



# 删除nginx-demo pod
kubectl delete po nginx-demo
# 根据配置文件创建pod
kubectl create -f nginx-demo.yaml
# 查看现在的pod
kubectl get po
# 查看pod描述
kubectl describe po nginx-demo
history



kubectl exec -it nginx-po bash -- cat /usr/share/nginx/html/prestop.html


# 监控po信息
kubectl get po -w

# 统计这条命令执行的时间
time kubectl delete po nginx-po
```

##### 3.pod配置文件

```yaml
apiVersion: v1          # api文档版本
kind: Pod               # 资源对象类型,也可以配置为像Deployment,StatefuSet这一类对象
metadata:               # Pod相关元数据,用于描述Pod的数据
  name: nginx-po      # Pod的名称
  labels:               # 定义Pod的标签
    type: app           # 自定义label标签,名称为type,值为app
    version: 1.0.0      # 自定义Pod版本号
  namespace: 'default'  # 命名空间配置
spec:                   # 期望Pod安装这里面的描述进行创建
  terminationGracePeriodSeconds: 40     # 当pod被删除时, 给pod执行收尾命令的时间
  containers:           # 对于Pod中的容器描述
  - name: nginx         # 容器名称
    image: nginx:1.7.9  # 指定容器的镜像
    imagePullPolicy: IfNotPresent       # 镜像拉取策略,如果本地有就用本地,没有就仓库拉取
    startupProbe:       # 应用启动探针配置
      #httpGet:          # 探针方式, 基于http请求探测
      #  path: /index.html                # http请求路径
      #  port: 80        # 请求端口
      tcpSocket:        # 建立连接成功 通过检查
        port: 80
      # exec:
      #  command:
      #    - sh
      #    - -c
      #    - "echo 'success' > /inited"
      failureThreshold: 3               # 超过3次算失败
      periodSeconds: 10 # 间隔时间
      successThreshold: 1               # 只要检测一次成功就算成功
      timeoutSeconds: 5 # 超时时间
    livenessProbe:      # 存活探针
      httpGet:          # 探针方式, 基于http请求探测
        path: /index.html                # http请求路径
        port: 80        # 请求端口
      #tcpSocket:        # 建立连接成功 通过检查
      #  port: 80
      # exec:
      #  command:
      #    - sh
      #    - -c
      #    - "echo 'success' > /inited"
      failureThreshold: 3               # 超过3次算失败
      periodSeconds: 10 # 间隔时间
      successThreshold: 1               # 只要检测一次成功就算成功
      timeoutSeconds: 5 # 超时时间
    readinessProbe:     # 就绪探针
      httpGet:
        path: /index.html
        port: 80
      failureThreshold: 3
      periodSeconds: 10
      successThreshold: 1
      timeoutSeconds: 5

    lifecycle:          # 生命周期配置
      postStart:        # 生命周期启动阶段做的事情,不移地在容器的command之前运行
        exec:
          command:
          - sh
          - -c
          - "echo '<h1>pre stop</h1>' > /usr/share/nginx/html/prestop.html"
      preStop:
        exec:
          command:
          - sh
          - -c
          - "sleep 50; echo 'sleep finished...' >> /usr/share/nginx/html/prestop.html"


    command:
    - nginx
    - -g
    - 'daemon off;'     # nginx -g 'daemon off;'
    workingDir: /usr/share/nginx/html   # 定义容器启动后的工作目录
    ports:
    - name: http        # 端口名称
      containerPort: 80 # 描述该端口内暴露什么算口
      protocol: TCP     # 描述该端口基于哪种协议通信的
    env:                # 环境变量
    - name: JVM_OPTS    # 环境变量名称
      value: '-Xms128m -Xmx128m'        # 环境变量值
    resources:
      requests:         # 最少需要多少资源
        cpu: 100m       # 限制cpu最少使用0.1个核心  1000m代表一个核心
        memory: 128Mi   # 限制内存最少使用128m
      limits:           # 最多可以使用多少资源
        cpu: 200m       # 限制cpu最多使用0.2个核心
        memory: 256Mi   # 限制内存最多使用256m
  restartPolicy: OnFailure      # 重启策略 只有失败的情况下重启
```

##### 4.探针

容器内应用的检测机制,根据同探针来判断容器当前状态

**探针类型**

```shell
# 启动探针 启动探针与其他探针互斥,会先禁用其他探针
# 在启动时判断应用是否成功启动
startupProbe:
  httpGet:				# 探针方式, 基于http请求探测
    path: /index.html 	# http请求路径
    port: 80			# 请求端口
   

# 存活探针 用于探测容器内应用是否运行
# 如果探测失败,可以根据重启策略进行重启,若没有配置,默认就认为容器启动成功,不会执行重启策略
livenessProbe:      # 存活探针
  tcpSocket:        # 建立连接成功 通过检查
    port: 80
  failureThreshold: 3 # 超过3次算失败
  periodSeconds: 10	# 间隔时间
  successThreshold: 1 # 只要检测一次成功就算成功
  timeoutSeconds: 5 # 超时时间


# 就绪探针 用户探测容器内程序是否见刊
# 返回值如果是success,那么久认为容器已经完全启动
readinessProbe:     # 就绪探针   httpGet:
  failureThreshold: 3 # 错误次数
  httpGet:
    path: /ready
    port: 8181
    scheme: HTTP
  periodSeconds: 10 # 间隔时间
  successThreshold: 1
  timeoutSeconds: 1

```

**探测方式**

```shell
# 命令探测 如果返回值为0,则任务容器健康
execAction

livenessProbe:
  exec:
    command:
    - cat
    - /health
    
 
# TCP连接检测容器内端口是否开放
TCPSocketAction

livenessProbe:
  tcpSocket:
  port: 80

# 生成环境用的比较多的方式
# 发送http请求到容器内应用程序,如果返回状态码在200~400之间,则容器健康
HTTPGetAction

livenessProbe:
  failureThreshold: 5
  httpGet:
    path: /health
    port: 8080
    scheme: HTTP
    httpHeaders:
      - name: xxx
        value: xxx
```

**参数配置**

```shell
initialDelaySeconds: 60	# 初始化时间
timeoutSeconds: 2		# 超时时间
periodSeconds: 5		# 检测间隔时间
successThreshold: 1		# 检查1次就能成功
failureThreshold: 2		# 检测失败2次表示失败
```

**生命周期**

```sh
初始化阶段	->
	初始化多个容器	->
->	以下基本同时执行
	startup启动探针	->
	command 容器命令执行	->
	postStart 启动钩子函数->
-> 
	readinessProbe 就绪探针	->
	livenessProbe 存活探针	->
	pod 内容器			   	->
->  
	livenessProbe 存活探针	->
	pod 内容器				->
->
	preStop 结束钩子函数
```



退出流程

```sh
Endpoint删除pod的ip地址 ->
pod变成Terminating状态  ->
执行preStop指定			->

# PreStop应用场景:
	注册中心下线
    数据清理
    数据销毁

```

```shell
# 需要注意默认删除pod,给定的时间为30s,30s后如果命令还没结束完,pod同样会删除
terminationGracePeriodSeconds: 30 

# 生命周期配置  配置钩子函数
lifecycle:
  postStart: # 容创建完成后执行的动作，不能保证该操作一定在容器的 command 之前执行，一般不使用
    exec: # 可以是 exec / httpGet / tcpSocket
      command:
        - sh
        - -c
        - 'mkdir /data'
  preStop: # 在容器停止前执行的动作
    httpGet: # 发送一个 http 请求
      path: /
      port: 80
    exec: # 执行一个命令
      command:
        - sh
        - -c
        - sleep 9

```

### 三.资源调度

#### deployment  无状态

##### 1.label

```shell
# 查看资源label
kubectl get po --show-labels

# 添加资源label 临时修改
kubectl label po nginx-po author=tower

# 覆盖
kubectl label po nginx-po author=test --overwrite

# 通过label去查找
kubectl label po -l type=app

# 显示pod 并且显示命名空间
kubectl label po -A -l

# 显示pod并且显示命名空间,和label
kubectl get po -A --show-labels


# 搜索lable中type=app的并且显示更多信息
kubectl get po -A -l type=app --show-labels

# label多个值匹配
kubectl get po -l 'version in (1.0.0, 1.1.1)'

# 多条件查找  与的关系   ''加不加都可以
kubectl get po -l author!=tower,version=1.0.0
```

##### 2.deployment 创建

```shell
# replica		复制品
# replicaset	复制盒子
# replica set	副本集
# deployment 	部署, 调集

deployment -> replicaSet -> pod

kubectl create deploy nginx-deploy --image=nginx:1.7.9

kubectl get deployments
kubectl get deploy
kubectl get replicaset

# 查看三个信息
kubectl get po,rs,deploy  --show-labels
```



```yaml
apiVersion: apps/v1				# deployment api版本
kind: Deployment				# 资源类型为deployment
metadata:						# 元信息
  labels:						# 标签
    app: nginx-deploy			# 具体的key:value配置形式
  name: nginx-deploy			# deployment的名称
  namespace: default			# 所在命名空间(默认)
spec:							# 规格
  replicas: 1					# 期望副本数
  revisionHistoryLimit: 10		# 运行滚动更新后,保留的历史版本数
  selector:						# 选择器,用于找到匹配replicaSet RS
    matchLabels:				# 按照标签匹配
      app: nginx-deploy			# 匹配标签kev/value
  strategy:						# 更新策略
    rollingUpdate:				# 滚动更新配置
      maxSurge: 25%				# 进行滚动更新时,更新的个数最odokeyi超过期望副本数的个数/比例
      maxUnavailable: 25%		# 进行滚动更新时,最大不可用比例比例,表示在所有副本中,最多可以有多少个不更新成功
    type: RollingUpdate			# 更新类型,采用滚动更新
  template:						# pod模板
    metadata:					# pod元信息
      labels:					# pod标签
        app: nginx-deploy
    spec:						# pod 期望信息
      containers:				# pod 的容器
      - image: nginx:1.7.9		# 镜像 
        imagePullPolicy: IfNotPresent	# 拉去策略
        name: nginx				# 容器名称
      restartPolicy: Always		# 重启策略
      terminationGracePeriodSeconds: 30	# 删除操作最多宽限时长
```



```yaml
apiVersion: apps/v1		
kind: Deployment
metadata:
  annotations:									# 描述信息 类似label
    deployment.kubernetes.io/revision: "1"
  creationTimestamp: "2023-07-07T02:45:00Z"		# 创建时间
  generation: 1									# 更新代数 当前第一版
  labels:
    app: nginx-deploy
  name: nginx-deploy							#
  namespace: default							# 命名空间 默认的
  resourceVersion: "84623"						# 资源版本
  uid: b0b0e589-b9b8-4426-829c-0366c49fe3d9		# id自动生成
spec:											# 规格
  progressDeadlineSeconds: 600					# 进度截止时间秒	
  replicas: 1									# 指定副本数量
  revisionHistoryLimit: 10						# 
  selector:										# 选择器
    matchLabels:								# 匹配label
      app: nginx-deploy							# 匹配这个label deployment通过这个关联replicaSet
  strategy:										# 策略
    rollingUpdate:								# 滚动更新策略
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:										# 模板 表述的pod
    metadata:
      creationTimestamp: null					# 创建时间戳
      labels:									
        app: nginx-deploy						
    spec:										# 规格
      containers:								# 容器			
      - image: nginx:1.7.9						# 镜像
        imagePullPolicy: IfNotPresent			# 镜像拉去策略
        name: nginx								# 名称
        resources: {}							# 资源
        terminationMessagePath: /dev/termination-log	# 删除时 消息路径
        terminationMessagePolicy: File					# 删除时 消息策略
      dnsPolicy: ClusterFirst					# dns策略
      restartPolicy: Always						# 重启策略
      schedulerName: default-scheduler			# 调度程序名称
      securityContext: {}						# 安全上下文
      terminationGracePeriodSeconds: 30			# pod删除是收尾执行时间
```

##### 3.deployment更新

**只有修改了deployment配置文件中的template中的属性才会触发更新操作**

```shell
# 进入编辑模式修改属性
kubectl edit deploy nginx-deploy

# 修改内部属性
kubectl set image deployment/nginx-deploy nginx=nginx:1.7.9;

# 查看deployment的信息
kubectl get deploy --show-labels


# 修改副本数  修改image版本1.9.1
# 查看deployment的详细描述
kubectl describe deploy nginx-deploy
#Events:
  Type    Reason             Age    From                   Message
  ----    ------             ----   ----                   -------
  Normal  ScalingReplicaSet  9m21s  deployment-controller  Scaled up replica set nginx-deploy-78d8bf4fd7 to 3
  Normal  ScalingReplicaSet  52s    deployment-controller  Scaled up replica set nginx-deploy-754898b577 to 1
  Normal  ScalingReplicaSet  40s    deployment-controller  Scaled down replica set nginx-deploy-78d8bf4fd7 to 2
  Normal  ScalingReplicaSet  40s    deployment-controller  Scaled up replica set nginx-deploy-754898b577 to 2
  Normal  ScalingReplicaSet  14s    deployment-controller  Scaled down replica set nginx-deploy-78d8bf4fd7 to 1
  Normal  ScalingReplicaSet  14s    deployment-controller  Scaled up replica set nginx-deploy-754898b577 to 3
  Normal  ScalingReplicaSet  12s    deployment-controller  Scaled down replica set nginx-deploy-78d8bf4fd7 to 0




# 查看更新输出
kubectl rollout status deploy nginx-deploy
#Waiting for deployment "nginx-deploy" rollout to finish: 1 out of 3 new replicas have been updated...
#Waiting for deployment "nginx-deploy" rollout to finish: 1 out of 3 new replicas have been updated...
#Waiting for deployment "nginx-deploy" rollout to finish: 1 out of 3 new replicas have been updated...
#Waiting for deployment "nginx-deploy" rollout to finish: 2 out of 3 new replicas have been updated...
#Waiting for deployment "nginx-deploy" rollout to finish: 2 out of 3 new replicas have been updated...
#Waiting for deployment "nginx-deploy" rollout to finish: 2 out of 3 new replicas have been updated...
#Waiting for deployment "nginx-deploy" rollout to finish: 1 old replicas are pending termination...
#Waiting for deployment "nginx-deploy" rollout to finish: 1 old replicas are pending termination...
#deployment "nginx-deploy" successfully rolled out
```

**多个滚动更新并行**

```sh
假设当前有 5 个 nginx:1.7.9 版本，你想将版本更新为 1.9.1，当更新成功第三个以后，你马上又将期望更新的版本改为 1.9.2，那么此时会立马删除之前的三个，并且立马开启更新 1.9.2 的任务
```

##### 4.deployment回滚

```shell
# 更新一个错误的镜像
kubectl set image deploy/nginx-deploy nginx=nginx1.91

# 查看rs
kubectl get rs --show-labels
#NAME                      DESIRED   CURRENT   READY   AGE     LABELS
#nginx-85b98978db          1         1         1       7d19h   app=nginx,pod-template-hash=85b98978db
#nginx-deploy-6767499d45   1         1         0       3m5s    app=nginx-deploy,pod-template-hash=6767499d45 更新出错版本
#nginx-deploy-754898b577   3         3         3       22m     app=nginx-deploy,pod-template-hash=754898b577 当前版本
#nginx-deploy-78d8bf4fd7   0         0         0       83m     app=nginx-deploy,pod-template-hash=78d8bf4fd7 第一个版本
# 以上有nginx-deploy三套模板  

# 查看正在更新pod的描述
kubectl describe po nginx-deploy-6767499d45

#Events:
  Type     Reason     Age                    From               Message
  ----     ------     ----                   ----               -------
  Normal   Scheduled  7m44s                  default-scheduler  Successfully assigned default/nginx-deploy-6767499d45-fbppz to k8s-node1
  Normal   Pulling    4m41s (x4 over 7m44s)  kubelet            Pulling image "nginx1.91"
  Warning  Failed     4m17s (x4 over 7m2s)   kubelet            Error: ErrImagePull
  Warning  Failed     4m5s (x6 over 7m2s)    kubelet            Error: ImagePullBackOff
  Normal   BackOff    3m54s (x7 over 7m2s)   kubelet            Back-off pulling image "nginx1.91"
  Warning  Failed     2m10s (x5 over 7m2s)   kubelet            Failed to pull image "nginx1.91": rpc error: code = Unknown desc = Error response from daemon: pull access denied for nginx1.91, repository does not exist or may require 'docker login': denied: requested access to the resource is denied



# 查看之前版本
kubectl rollout history deploy/nginx-deploy

# 版本 	 修改的原因
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>

# 在更改配置时加入更改注释
kubectl set images deploy/nginx-deploy nginx=nginx:1.7.9 --record 原因

# 指定查看某个版本的信息
kubectl rollout history deploy/nginx-deploy --revision=2


# 版本回退到指定版本
kubectl rollout undo deploy/nginx-deploy --to-revision=2'
# 查看滚动状态
kubectl rollout status deploy/nginx-deploy

```

##### 5.扩容和缩容

```shell
# 扩容副本数 
kubectl scale --replicas=6 deploy nginx-deploy

# deploy不变  rs内副本数变化  pod个数变成副本数
kubectl get deploy,rs,pod

# 减少 缩容
kubectl scale --replicas=4 deploy nginx-deploy 
```

##### 6.暂停恢复

```shell
# 由于每次对pod template中的信息发生修改后,都会触发deployment操作,那么此时对如果频繁修改信息,就会产生多次更新,而实际上只需要一次更新即可,此时可以暂停deploymenet的rollout
kubectl rollout pause deploy nginx-deploy

# 恢复
kubectl rollout resume deploy nginx-deploy

# 查看历史版本
kubectl rollout history deploy nginx-deploy

# 查看指定历史版本信息
kubectl rollout history deploy nginx-deploy --revision=5

```

#### StatefulSet 有状态

##### 1.小知识

```sh
state 状态
stateful 有状态的
stateful set 有状态集

在yaml中  --- 代表嵌套
```

##### 2.yaml配置文件

```yaml
---						# yaml嵌套
apiVersion: v1			#
kind: Service			# 类型
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None
  selector:
    app: nginx			# 绑定  找到app=nginx的应用 
---
apiVersion: apps/v1		# 版本号
kind: StatefulSet		# StatefulSet类型资源
metadata:				# 元数据
  name: web				# StatefulSet 资源名称
spec:					# 规格
  serviceName: "nginx"	# 使用哪个service来管理dns
  replicas: 2			# 副本数
  selector:
    matchLabels:
      app: nginx
  template:				# pod模板
    metadata:			# pod元数据
      labels:			# labes
        app: nginx		# app=nginx
    spec:				# 容器规格
      containers:		# 容器
      - name: nginx		# 容器名称
        image: nginx:1.7.9	# 镜像
        ports:			# 容器内端口设置
        - containerPort: 80	# 容器内暴露端口
          name: web		# 端口名称
        volumeMounts:	# 加载数据卷
        - name: www		# 指定加载哪个数据卷
          mountPath: /usr/share/nginx/html	# 容器内数据目录
  volumeClaimTemplates:	# 数据卷模板
  - metadata:			# 数据卷描述
      name: www			# 数据卷名称
      annotations:		# 数据卷注解  元信息的描述
        volume.alpha.kubernetes.io/storage-class: anything
    spec:				# 数据卷的规约
      accessModes: [ "ReadWriteOnce" ]	# 访问模式
      resources:
        requests:
          storage: 1Gi	# 需要1个G的资源
```

##### 3.StatefulSet操作命令

```shell
# 获取statefulSet资源状态
kubectl get statefulset
kubectl get sts

# 删除一个statefulSet资源的 有状态资源是分开的
kubectl delete sts web
kubectl delete svc nginx
kubectl delete pvc www-web-0
  
# 创建statefulset  
kubectl create -f web.yaml  

# 查看资源
kubectl get sts
kubectl get svc
kubectl get pvc
kubectl describe pvc www-web-0

# 替换  但是出了问题不能替换
# kubectl replace sts web  -f web.yaml
```

##### 4.测试网络工具

```sh
# 容器小工具 busybox 						退出后删除
kubectl run -it --image busybox:1.28.4 dns-test --restart=Never --rm  /bin/sh


#.namespace.svc.cluster.local 可以省略
statefulSet中每个pod的dns格式为statefulSetName-{0,...N-1}.serviceName.namespace.svc.cluster.local

# dns映射信息
nslookup web-0.nginx
#Server:    10.96.0.10
#Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
#Name:      web-0.nginx
#Address 1: 10.244.36.84 web-0.nginx.default.svc.cluster.local
```

##### 5.扩容缩容

```shell
kubectl scale sts web --replicas=5

kubectl describe sts web
# 具有顺序性
#Events:
  Type    Reason            Age   From                    Message
  ----    ------            ----  ----                    -------
  Normal  SuccessfulCreate  15m   statefulset-controller  create Pod web-0 in StatefulSet web successful
  Normal  SuccessfulCreate  15m   statefulset-controller  create Pod web-1 in StatefulSet web successful
  Normal  SuccessfulCreate  27s   statefulset-controller  create Pod web-2 in StatefulSet web successful
  Normal  SuccessfulCreate  26s   statefulset-controller  create Pod web-3 in StatefulSet web successful
  Normal  SuccessfulCreate  25s   statefulset-controller  create Pod web-4 in StatefulSet web successfu
  
# 缩容
kubectl patch statefulset web -p '{"spec":{"replicas":3}}'
kubectl scale sts web --replicas=2
```

##### 6.镜像更新

###### **滚动更新**

```shell
# 目前不支持image更新,需要patch来间接实现 edit也可以 或者set image

kubectl patch sts web --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"nginx:1.9.1"}]'

kubectl rollout history sys web
kubectl rollout history sys web --revision=2

kubectl get sts web -o wide

partition: 3
```

###### **金丝雀发布/灰度发布**

```shell
  updateStrategy:
    rollingUpdate:
      partition: 3		# 需要大于等于3的更新 即 3,4更新
    type: RollingUpdate

kubectl get po -o wide
kubectl get describe po web-4
```

###### **ondelete 删除pod后才更更新**

```shell
  updateStrategy:
    rollingUpdate:
      partition: 1
    type: RollingUpdate
->
  updateStrategy:
   type: onDelete		# 当删除才更新
   
for i in {0..4};do echo -e "web-${i}:$(kubectl describe pod web-${i}|grep "Image:")";done
```

##### 7.StatefulSet删除

```shell
# 删除statefulset和headless service
# 级联删除
# 删除statefulset时会同时删除pods
kubectl delete sts web

# 非级联删除
kubectl delete sts web --cascade=false

# 删除service
kubectl delete svc nginx

# 删除pvc
kubectl delete pvc www-web-0
```

#### DaemonSet

##### 1.小知识

```shell
daemonset 后台程序集
# 没有副本概念 一个节点就是一个
```

##### 2.yaml配置文件

```yaml
apiVersion: apps/v1
kind: DaemonSet		# 资源类型 daemonSet
metadata:			# 元数据
  name: fluentd		# 名字
spec:	
  selector:
    matchLabels:
      app: logging
  template:
    metadata:
      labels:
        app: logging
        id: fluentd
      name: fluentd	# pod名称
    spec:
      nodeSelector:
        type: microservices
      containers:
      - name: fluentd-es	# 容器名称
        image: agilestacks/fluentd-elasticsearch:v1.3.0	# 镜像
        env:		# 环境变量
         - name: FLUENTD_ARGS	# 环境变量的key
           value: -qq			# 环境变量的value
        volumeMounts:			# 加载数据卷.避免数据丢失
         - name: containers		# 数据卷的名字
           mountPath: /var/lib/docker/containers	# 容器内数据位置
         - name: varlog
           mountPath: /varlog
      volumes:	# 定义数据卷
         - hostPath:	# 数据卷类型,主机路径的模式,也就是与node共享目录
             path: /var/lib/docker/containers	# node中的共享目录
           name: containers		# 定义数据卷的名称
         - hostPath:
             path: /var/log
           name: varlog


```

##### 3.DaemonSet操作命令

```sh
# 获取DeamondSet状态
kubectl get daemonset
kubectl get ds
# 查看pod
kubectl get po
# 查看描述信息
kubectl describe po fluentd-dbd2j

# 给节点添加标签
# 通过对应的selector选择label 进行对节点的deamondSet安装
kubectl label no k8s-node1 type=microservices
# 查看pod的label
kubectl get no --show-labels

# 编辑deamonSet的配置
kubectl edit ds fluentd

# 添加 对节点的选择
spec:
  template:
    spec:
      nodeSelector:
        type: microservices
        
        
# 查看deamonSet的信息
kubectl get ds
# 通过条件查找pod信息
kubectl get po -l app=logging
# 通过条件查找pod且显示更多信息
kubectl get po -l app=logging -o wide
# 给k8s-node2节点添加标签 
kubectl label no k8s-node2 type=microservices


# DaemonSet中RollingUpdate与Deployment的RollingUppdate的属性是一致的,采用滚筒更新的策略
# SttatefluSet中的RollingUpdate的属性则采用的是金丝雀发布策略

# 建议把UpdateStrategy中的type改为onDelete
```

#### HPA自动扩容

##### 1.小知识

```shell
# 通过观察pod的cpu,内存使用率或自定义metrics指标进行自动的扩容或缩容pod的数量
# 通常用于deployment,不适用于无法扩/缩容的对象,如DaemonSet
# 控制管理器每30s(可以通过-horizontal-pod-autoscaler-sync-period修改)查询metrics的资源使用情况

# 实现cpu或内存监控,首先有个前提条件,该对象必须配置了resources.requests.cpu或resources.requests.memory才可以,可以配置当cpu/menory达到上述配置的百分比后进行扩容或缩容
```

##### 2.yaml配置文件

```shell

# 创建
kubectl create -f nginx-deployment.yaml

# 添加
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 128Mi

# 替换
kubectl replace -f nginx-deployment.yaml

# 创建一个HPA  
kubectl autoscale deploy nginx-deploy --cpu-percent=20 --min=2 --max=5
```

##### 3.metrics-server安装

```shell
# 收集和存储集群中的资源利用率数据和指标信息
# 下载 metrics-server 组件配置文件
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -O metrics-server-components.yaml

# 修改镜像地址为国内的地址 替换文件内容
sed -i 's/k8s.gcr.io\/metrics-server/registry.cn-hangzhou.aliyuncs.com\/google_containers/g' metrics-server-components.yaml

# 修改容器的 tls 配置，不验证 tls，在 containers 的 args 参数中增加 --kubelet-insecure-tls 参数
containers:
  - args:
    - --kubectl-insecure-tls  # 添加信任tls


# 安装组件
kubectl apply -f metrics-server-components.yaml

# 查看 pod 状态
kubectl get pods --all-namespaces | grep metrics


# 
apiVersion: v1                  #
kind: Service                   # 类型
metadata:
  name: nginx-svc
  labels:
    app: nginx
spec:
  selector:
    app: nginx-deploy
  ports:
  - port: 80
    targetPort: 80
    name: web
  type: NodePort
  
 							主机端口					容器端口:宿主机端口 
#NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
#kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP        8d
#nginx-svc    NodePort    10.102.232.72   <none>        80:30187/TCP   6s'
192.168.28.120:30187
10.102.232.72:80



# 测试：找到对应服务的 service，编写循环测试脚本提升内存与 cpu 负载
while true; do wget -q -O- http://<ip:port> > /dev/null ; done
while true; do wget -q -O- http://10.102.232.72:80 /dev/null ; done


# 查看hpa信息
kubectl get hpa


# 自定义metrics
控制管理器开启–horizontal-pod-autoscaler-use-rest-clients
控制管理器的–apiserver指向API Server Aggregator
在API Server Aggregator中注册自定义的metrics API


kubectl get endpoints
kubectl get ep
```

### 四.服务发布

#### service

##### 1.小知识

```shell
service 通常用于服务之间的相互调用  (东西流量)

# 服务发现: 为应用程序提供一个稳定网络入口,其他应用程序可以通过service名称和算口来访问服务,而不需要关心pod的具体ip地址和端口
# 负载均衡: 可以将请求均匀的分发到多个pod实例上,实现负载均衡.他会自动检测后端pod的健康状态,并根据需要动态地更新可用后端的pod列表
# 服务间通信: 实现不同服务之间的通信,无论这些服务是否部署在同一个节点上.他提供了一个虚拟的ip地址和端口
# 服务带里: 可作为带里,将请求转发到pod上,同时隐藏后端pod的具体细节
```

##### 2.yaml配置文件

```yaml
apiVersion: v1		#
kind: Service		# 资源类型为service
metadata:			
  name: nginx-svc	# service名称
  labels:			# service自身标签
    app: nginx
spec:				# 
  selector:			# 匹配哪些pod
    app: nginx-deploy	# 所有匹配到的标签的pod都可以通过service进行访问
  ports:			# 端口映射
  - port: 80		# service自己端口.可以在内网ip访问时使用
    targetPort: 80	# 目标pod的端口
    name: web		# 为端口的名字
  type: NodePort	# 四种类型ClusterIP ExternalName Nodeport LoadBalancer
  					# NodePort随机启动一个端口(30000-32767),映	射到ports中的端口,该端口是直接绑定在node上,且集群中的每一个node都会绑定这个端口
  					# 也可以用于将服务暴露给外部访问,但是这种方式实际生产环境中不推荐,效率底
  					# 而且service是四层负载
```

##### 3.service操作命令

```shell
# 获取services信息
kubectl get svc
# 查看serveric 中的 nginx-svc描述
kubectl describe svc nginx-svc
# 创建busybosx工具
kubectl run -it --image busybox:1.28.4 dns-test
# 进入busybox测试工具
kubectl exec -it dns-test -- sh
# 通过serviceName进行访问
wget http://nginx-svc.default
```

##### 4.endpoints

```sh
# 用于将Service与其后端Pod的网络终点（IP和端口）关联起来
# Endpoints资源记录了Service所代表的服务的实际后端Pod的网络终点信息

# 服务发现: endpoints定义了service所关联的后端pod的网络终点,使得起应用程序可以通过service名称和端口来访问这些pod,当service被创建或更新时,kubernetes会自动更新endpoints,确保service与后端pod的关联式最新的
# 负载均衡: 记录了后端pod的ip地址和端口信息,service通过这些信息将请求均匀的分发给后端pod上,实现负载均衡.
# 动态更新: 当后端pod的ip地址或端口发生变化时,kubernetes会自动更新endpoints,确保service与后端pod的关联式最新的
```

yaml配置文件

```yaml
apiVersion: v1
kind: Endpoints
metadata:
  labels:
    app: wolfcode-svc-external # 与 service 一致
  name: wolfcode-svc-external # 与 service 一致
  namespace: default # 与 service 一致
subsets:
- addresses:
  - ip: <target ip> # 目标 ip 地址
  ports: # 与 service 一致
  - name: http
    port: 80
    protocol: TCP
```

#### ingresss

##### 5.安装helm

```shell
wget https://get.helm.sh/helm-v3.2.3-linux-amd64.tar.gz
tar -zxvf helm-v3.2.3-linux-amd64.tar.gz

# 将解压目录下的helm程序移动到/usr/local/bin/下
mv helm /usr/local/bin/


# 添加仓库
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# 查看仓库列表
helm repo list


# 搜索ingress-nginx
helm search repo ingress-nginx

# 下载
helm pull ingress-nginx/ingress-nginx
# 解压
tar xf ingress-nginx-xxx.tgz

# 修改 values.yaml
镜像地址：修改为国内镜像
registry: registry.cn-hangzhou.aliyuncs.com
image: google_containers/nginx-ingress-controller
image: google_containers/kube-webhook-certgen
tag: v1.3.0

hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet

修改部署配置的 kind: DaemonSet
nodeSelector:
  ingress: "true" # 增加选择器，如果 node 上有 ingress=true 就部署
将 admissionWebhooks.enabled 修改为 false
将 service 中的 type 由 LoadBalancer 修改为 ClusterIP，如果服务器是云平台才用 LoadBalancer

```

##### 6.安装ingress控制器

```shell
# 创建门存放的命名空间
kubectl create  ns ingress-nginx
# 为需要安装的节点 添加标签
# kubectl label node k8s-master ingress=true
kubectl label no k8s-node1 ingress=true

# 创建ingress控制器
helm install ingress-nginx -n ingress-nginx .

# 查看node标签
kubectl get no --show-labels


wget wolfcode-external-domain
```

记一次排错

```shell
# 查看日志
kubectl logs ingress-nginx -n ingress-nginx
# 查看状态
helm status ingress-nginx -n ingress-nginx
# 删除 准备重装
helm uninstall ingress-nginx -n ingress-nginx
```

##### 7.ingress资源yaml配置文件

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress # 资源类型为 Ingress
metadata:
  name: wolfcode-nginx-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules: # ingress 规则配置，可以配置多个
  - host: k8s.wolfcode.cn # 域名配置，可以使用通配符 *
    http:
      paths: # 相当于 nginx 的 location 配置，可以配置多个
      - pathType: Prefix # 路径类型，按照路径类型进行匹配 ImplementationSpecific 需要指定 IngressClass，具体匹配规则以 IngressClass 中的规则为准。Exact：精确匹配，URL需要与path完全匹配上，且区分大小写的。Prefix：以 / 作为分隔符来进行前缀匹配
        backend:
          service: 
            name: nginx-svc # 代理到哪个 service
            port: 
              number: 80 # service 的端口
        path: /api # 等价于 nginx 中的 location 的路径前缀匹配
```

多域名配置

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress # 资源类型为 Ingress
metadata:
  name: wolfcode-nginx-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules: # ingress 规则配置，可以配置多个
  - host: k8s.wolfcode.cn # 域名配置，可以使用通配符 *
    http:
      paths: # 相当于 nginx 的 location 配置，可以配置多个
      - pathType: Prefix # 路径类型，按照路径类型进行匹配 ImplementationSpecific 需要指定 IngressClass，具体匹配规则以 IngressClass 中的规则为准。Exact：精确匹配，URL需要与path完全匹配上，且区分大小写的。Prefix：以 / 作为分隔符来进行前缀匹配
        backend:
          service:
            name: nginx-svc # 代理到哪个 service
            port:
              number: 80 # service 的端口
        path: /api # 等价于 nginx 中的 location 的路径前缀匹配

      - pathType: Exact  # 路径类型，按照路径类型进行匹配 ImplementationSpecific 需要指定 IngressClass，具体匹配规则以 IngressClass 中的规则为准。Exact：精确匹配，URL需要与path完全匹配上，且区分大小写的。Prefix：以 / 作为分隔符来进行前缀匹配
        backend:
          service:
            name: nginx-svc # 代理到哪个 service
            port:
              number: 80 # service 的端口
  - host: api.wolfcode.cn # 域名配置，可以使用通配符 *
    http:
      paths: # 相当于 nginx 的 location 配置，可以配置多个
      - pathType: Prefix # 路径类型，按照路径类型进行匹配 ImplementationSpecific 需要指定 IngressClass，具体匹配规则以 IngressClass 中的规则为准。Exact：精确匹配，URL需要与path完全匹配上，且区分大小写的。Prefix：以 / 作为分隔符来进行前缀匹配
        backend:
          service:
            name: nginx-svc # 代理到哪个 service
            port:
              number: 80 # service 的端口
        path: /api # 等价于 nginx 中的 location 的路径前缀匹配
```

```shell
kubectl create -f wolfcide-ingress.yaml
netstat -ntlp
# 在本机hosts中添加映射 
# 浏览器中可通过域名直接访问
http://k8s.wolfcode.cn/api/index.html
```

### 存储与配置

##### ConfigMap

```shell
# 存储pod中应用所需要的配置信息,或者环境变量,将置于pod分开,避免因为修改配置导致还需要重新构建镜像与容器

kubectl create configmap test-dir-config --from-file=test/

kubectl get cm
kubectl get configmap
kubectl describe cm test-dir-config
kubectl create cm spring-boot-test-alises-yaml --from-file=/opt/k8s/config/application.yml
kubectl create cm spring-boot-test-alises-yaml --from-file=app.yml=/opt/k8s/config/application.yml

kubectl create cm -h
# Examples:
  # Create a new config map named my-config based on folder bar
  kubectl create configmap my-config --from-file=path/to/bar

  # Create a new config map named my-config with specified keys instead of file basenames on disk
  kubectl create configmap my-config --from-file=key1=/path/to/bar/file1.txt --from-file=key2=/path/to/bar/file2.txt

  # Create a new config map named my-config with key1=config1 and key2=config2
  kubectl create configmap my-config --from-literal=key1=config1 --from-literal=key2=config2

  # Create a new config map named my-config from the key=value pairs in the file
  kubectl create configmap my-config --from-file=path/to/bar

  # Create a new config map named my-config from an env file
  kubectl create configmap my-config --from-env-file=path/to/foo.env --from-env-file=path/to/bar.env






# 创建test-env-config 的configmap
kubectl create cm test-env-config --from-literal=JAVA_OPTS_TEST='-Xms512m -Xmx512m' --from-literal=APP_NAME=sprinboot_env_test
```

使用configmap的pod

env-test-pod.yaml

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-env-po
spec:
  containers:
    - name: env-test
      image: alpine
      command: ["/bin/sh", "-c", "env; sleep 3600"]
      imagePullPolicy: IfNotPresent
      env:
      - name: JAVA_VM_OPTS
        valueFrom:
          configMapKeyRef:
            name: test-env-config       # configMap的名字
            key: JAVA_OPTS_TEST         # 表示从name的ConfigMap中获取key的value,将其赋值给本地环境变量JAVA_VM_OPTS
      - name: APP
        valueFrom:
          configMapKeyRef:
            name: test-env-config
            key: APP_NAME

  restartPolicy: Never
```

```shell
#  查看pods日志 是否输出了env
kubectl logs -f test-env-po
```

file-test-pod.yaml

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-configfile-po
spec:
  containers:
    - name: config-test
      image: alpine
      command: ["/bin/sh", "-c", "env; sleep 3600"]
      imagePullPolicy: IfNotPresent
      env:
      - name: JAVA_VM_OPTS
        valueFrom:
          configMapKeyRef:
            name: test-env-config       # configMap的名字
            key: JAVA_OPTS_TEST         # 表示从name的ConfigMap中获取key的value,将其赋值给本地环境变量JAVA_VM_OPTS
      - name: APP
        valueFrom:
          configMapKeyRef:
            name: test-env-config
            key: APP_NAME
      volumeMounts:     # 加载数据卷
      - name: db-config # 表示加载volumes属性中哪个数据卷
        mountPath: "/usr/local/mysql/conf"      # 想要将数据卷中的文件加载哪个目录下
        readOnly: true  # 是否为只读

  volumes:      # 数据卷挂载 configmap, secret
    - name: db-config   # 数据卷名字,随意设置
      configMap:        # 数据卷类型为configMap
        name: test-dir-config   # configMap的名字.必须跟想要加载的configmap相同
        items:          # 对configmap中的eky进行映射,如果不指定,默认会将configmap中所有key全部转换为一个同名文件
        - key: "db.properties"  # configMap中的key
          path: "db.properties" # 将该可以的值转换为文件
  restartPolicy: Never

```



```shell
# 进入  查看一下env
kubectl exec -it test-configfile-po -- sh
```









##### 加密数据配置secret

```sh
secret 秘密

# 与ConfigMap类似,用于存储配置信息,但是主要用于存储敏感新冰箱,需要加密信息,Secret可以提供数据加密,解密功能
# 在创建Secret,要注意如果加密字符中包含特殊字符,需要使用转义字符转义,例如$转义字符后为\$,也可以对特殊字符使用单引号描述,这样就可需要转义,例如:1$289*-!转换为'1$289*-!'
```



```shell
# 创建加密secret
kubectl create secret generic orig-secret --from-literal=username=amdin --from-literal=password='123@123'

# 查看创建帮助
kubectl create secret -h
kubectl create secret docker-registry -h

# 查看secret
kubectl get secret

# 他的加密其实是个base64转码
echo 'admin' | base64
echo 'YWRtaW4K' | base64 -d

# 创建docker registry的信息
kubectl create secret docker-registry harbor-secret --docker-username=amdin --docker-password=wolfcode --docker-email=liugang@wolfcode.cn --docker-server=192.168.113.122:8858

# 使用解码
 echo 'eyJhdXRocyI6eyJodHRwczovL2luZGV4LmRvY2tlci5pby92MS8iOnsidXNlcm5hbWUiOiJhbWRpbiIsInBhc3N3b3JkIjoid29sZmNvZGUiLCJlbWFpbCI6ImxpdWdhbmdAd29sZmNvZGUuY24iLCJhdXRoIjoiWVcxa2FXNDZkMjlzWm1OdlpHVT0ifX19' | base64 --decode
{"auths":{"https://index.docker.io/v1/":{"username":"amdin","password":"wolfcode","email":"liugang@wolfcode.cn","auth":"YW1kaW46d29sZmNvZGU="}}}
```

**docker仓库的登录上传退出登录**

```shell
docker tag nginx:1.9.1 192.168.113.122:8858/opensource/nginx:1.9.1

docker login -uadmin 192.168.113.12:8858 
docker push 192.168.113.122:8858/opensource/nginx:1.9.1

docker logout 192.168.113.122
```

通过私人仓库建立的一个pod

```yaml
# private-image-pull-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: private-image-pull-pod
spec:
  imagePullSecrets:     # 配置登录docker registry的secret
  - name: harbor-secret
  containers:
    - name: config-test
      image: 192.168.113.122:8858/opensource/nginx:1.9.1
      command: ["/bin/sh", "-c", "env; sleep 3600"]
      imagePullPolicy: IfNotPresent
      env:
      - name: JAVA_VM_OPTS
        valueFrom:
          configMapKeyRef:
            name: test-env-config       # configMap的名字
            key: JAVA_OPTS_TEST         # 表示从name的ConfigMap中获取key的value,将其赋值给本地环境变量JAVA_VM_OPTS
      - name: APP
        valueFrom:
          configMapKeyRef:
            name: test-env-config
            key: APP_NAME
      volumeMounts:     # 加载数据卷
      - name: db-config # 表示加载volumes属性中哪个数据卷
        mountPath: "/usr/local/mysql/conf"      # 想要将数据卷中的文件加载哪个目录下
        readOnly: true  # 是否为只读

  volumes:      # 数据卷挂载 configmap, secret
    - name: db-config   # 数据卷名字,随意设置
      configMap:        # 数据卷类型为configMap
        name: test-dir-config   # configMap的名字.必须跟想要加载的configmap相同
        items:          # 对configmap中的eky进行映射,如果不指定,默认会将configmap中所有key全部转换为一个同名文件
        - key: "db.properties"  # configMap中的key
          path: "db.properties" # 将该可以的值转换为文件
  restartPolicy: Never

```

##### SubPath的使用

```shell
# 创建一个ConfigMap
kubectl create cm nginx-conf-cm --from-file=./nginx.conf
# 查看ConfigMap的描述
kubectl describe cm nginx-conf-cm
```



```sh
# nginx-conf-cm describe
Name:         nginx-conf-cm
Namespace:    default
Labels:       <none>
Annotations:  <none>

Data
====
nginx.conf:
----

user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    include /etc/nginx/conf.d/*.conf;
}



BinaryData
====

Events:  <none>
```



**使用数据卷会覆盖原有目录**

```yaml

spec:
  progressDeadlineSeconds: 600
  replicas: 2
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: nginx-deploy
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: nginx-deploy
    spec:
      containers:
      - image: nginx:1.7.9
        imagePullPolicy: IfNotPresent
        name: nginx
        resources:
          limits:
            cpu: 200m
            memory: 128Mi
          requests:
            cpu: 10m
            memory: 128Mi
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        volumeMounts:             # 挂载数据卷
        - name: nginx-conf        # 数据卷的名字
          mountPath: '/etc/nginx/nginx.conf' # 挂载的路径  nginx.conf subPath'
          subPath: etc/nginx/nginx.conf # subPath
      volumes:                    # 数据卷的定义
      - name: nginx-conf          # 定义数据卷的名称
        configMap:                # 数据卷的类型为configMap
          name: nginx-conf-cm     # configmap中的名字
          items:                  # 要configmap中的哪些数据挂载进来
          - key: nginx.conf       # 指定挂载到哪个key上
            path: etc/nginx/nginx.conf      # 挂载后该key重命名为什么名 subPath
            
            
# 配置方式：
#定义 volumes 时需要增加 items 属性，配置 key 和 path，且 path 的值不能从 / 开始
#在容器内的 volumeMounts 中增加 subPath 属性，该值与 volumes 中 items.path 的值相同
containers:
  ......
  volumeMounts:
  - mountPath: /etc/nginx/nginx.conf # 挂载到哪里
    name: config-volume # 使用哪个 configmap 或 secret
    subPath: etc/nginx/nginx.conf # 与 volumes.[0].items.path 相同
volumes:
- configMap:
  name: nginx-conf # configMap 名字
  items: # subPath 配置
    key: nginx.conf # configMap 中的文件名
    path: etc/nginx/nginx.conf # subPath 路径
         
```

##### 配置热更新

```shell
# 默认方式 
	# 修改后会更新,更新周期是更新时间+缓存时间
# SubPath
	# 不会更新变量形式:如果pod中的一个变量时从configMapt中或secret中得到,统样也是不会更小的
	# 对于subPath的方式我们可以取消subPath的使用,将配置文件挂载到一个不存在的目录,避免目录覆盖,然后在利用软连接的形式,将该文件链接到目录位置
```

```shell
# 通过
kubectl edit cm test-dir-pod.yaml

# 通过replcae替换
# 由于 configmap 我们创建通常都是基于文件创建，并不会编写 yaml 配置文件，因此修改时我们也是直接修改配置文件，而 replace 是没有 --from-file 参数的，因此无法实现基于源配置文件的替换，此时我们可以利用下方的命令实现
# 该命令的重点在于 --dry-run 参数，该参数的意思打印 yaml 文件，但不会将该文件发送给 apiserver，再结合 -oyaml 输出 yaml 文件就可以得到一个配置好但是没有发给 apiserver 的文件，然后再结合 replace 监听控制台输出得到 yaml 数据即可实现替换
kubectl create cm test-dir-config  --from-file=./test/ --dry-run -o yaml | kubectl 
replace -f-
```

##### 不可变Secret和ConfigMap

```shell
#对于一些敏感服务的配置文件，在线上有时是不允许修改的，此时在配置 configmap 时可以设置 immutable: true 来禁止修改


apiVersion: v1
data:
  db.properties: |+
    useranme=tower
    password=123456

  redis.prorpeties: |
    host: 127.0.0.1
    port: 6379
kind: ConfigMap
metadata:
  creationTimestamp: "2023-07-08T15:06:09Z"
  name: test-dir-config
  namespace: default
  resourceVersion: "225865"
  uid: 64253fff-2277-466d-90d9-75dcfb826d68
immutable: true		# 设置不能在更改
```



### 持久化存储

#### volumes  

##### hostPath本地

```shell
# 将节点上的文件或目录挂载到pod上,此时该目录会变成持久化存储目录,即使将pod删除后重启,也可以重新加载到该目录,该目录下文件不会丢失
```

```yaml
# volume-test-pd.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-volume-pd
spec:
  containers:
  - image: nginx
    name: nginx-volume
    volumeMounts:
    - mountPath: /test-pd # 挂载到容器的哪个目录
      name: test-volume # 挂载哪个 volume
  volumes:
  - name: test-volume
    hostPath:		# 与主机共享目录,加载主机中的指定目录到容器中
      path: /data 	# 节点中的目录
      type: DirectoryOrCreate # 检查类型，在挂载前对挂载目录做什么检查操作，有多种选项，默认为空字符串，不做任何检查
      
#类型:
	# 空字符串: 默认类型,不做任何检查
	# DirectoryOrCreate: 如果给定path不存在,就创建一个755的空目录
	# Directory: 这个目录必须存在
	# FileOrCreate: 如果文件不存在,则创建一个空文件,权限为644
	# Socket: UNIX套接字,必须存在
	# CharDevice: 字符设备,必须存在
	# BlockDevice: 块设备,必须存在
```

##### enptryDir

```shell
# 用于一个车pod中的不同container共享数据使用,由于只是在pod内部使用,因此与其他volumen比较大的区别式,当pod如果被删除了,那么enptyDir也会被删除

# 存储介质可以是任意类型,如果SSD,磁盘或网络存储.可以将emtyDir.medium设置为Memory让k8s使用tmpfs(内存支持文件系统),速度比较快,但是重启tmpfs节点时,数据会被清除,且设置的大小会计入Container的内存限制中.
```

```yaml
# empty-dir-pd.yaml
apiVersion: v1
kind: Pod
metadata:
  name: empty-dir-pd
spec:
  containers:
  - image: alpine
    name: alpine-emptydir1
    command: ["/bin/sh", "-c", "sleep 3600;"]
    volumeMounts:
    - mountPath: /cache
      name: cache-volume

  - image: alpine
    name: alpine-emptydir2
    command: ["/bin/sh", "-c", "sleep 3600;"]
    volumeMounts:
    - mountPath: /opt
      name: cache-volume

  volumes:
  - name: cache-volume
    emptyDir: {}
```

```shell
# 进入一个pod的中的一个容器
kubectl exec -it empty-dir-pd -c alpine-emptydir1 -- sh
```

#### NFS

```shell
# nfs卷能将NFS(网络文件系统)挂载到你的Pod.不想emptyDir那样会删除Pod的同时也会删除,nfs卷的内容在删除pod时,会被保存,卷只是被卸载,这意味着nfs卷可以预先填充数据,并且这些数据可以在pod之间共享.
```

安装nfs

```shell
# 安装 nfs
yum install nfs-utils -y

# 启动 nfs
systemctl start nfs-server
# 开机自启
systemctl status nfs-server

df -h

# 查看 nfs 版本
cat /proc/fs/nfsd/versions

# 创建共享目录
mkdir -p /data/nfs
cd /data/nfs
mkdir rw
mkdir ro

# 设置共享目录 export
vim /etc/exports
/home/nfs/rw 192.168.28.0/24(rw,sync,no_subtree_check,no_root_squash)
/home/nfs/ro 192.168.28.0/24(ro,sync,no_subtree_check,no_root_squash)

# 重新加载
exportfs -f
systemctl reload nfs-server

# 到其他测试节点安装 nfs-utils 并加载测试
mkdir -p /mnt/nfs/rw
mount -t nfs 192.168.28.121:/home/nfs/rw /mnt/nfs/rw
mount -t nfs 192.168.28.121:/home/nfs/ro /mnt/nfs/ro

unmount
```

```yaml
# nfs-test-pd.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nfs-test-pd1
spec:
  containers:
  - image: nginx
    name: test-container
    volumeMounts:
    - mountPath: /usr/share/nginx/html
      name: test-volume
  volumes:
  - name: test-volume
    nfs:
      server: 192.168.28.121 # 网络存储服务地址
      path: /home/nfs/rw/www/wolfcode # 网络存储路径
      readOnly: false # 是否只读
```

#### PV与PVC

##### 生命周期

```sh
Persistent  持续的
retain	保持
claim	要求
# persistentVolumen 持久卷
# PersistentVolumeClaim	持久卷申领
```

**构建**

```sh
# 静态构建
# 己去管理原创建若干PV卷,这些卷对象带有真实存储的细节,并且对集群用户可以将.
# pv卷对象存在kubernetes API中可供用户消费使用.

# 动态构建
# 如果集群中已经有PV无法满足PVC的需求,那么集群会根据PVC自动构建一个PV,该操作时通过StroageClass实现的.
# 想实现这个操作,前提是PVC必须设置StorageClass,否则无法动态构建PV,可以通过启动DefaultStorageClass来实现PV的构建
```

**绑定**

```sh
# 当用户创建一个PVC对象后,主节点会检测匹配新的PVC对象,丙炔寻找与之匹配的PV卷,找到PV卷后将二者绑定在一起
######################
# 如果找不到对应PV,则需要看PVC是否设置StorageClass决定是否动态创建PV,若没有配置,PVC就会一直处于未绑定,知道有与之匹配的PV后才会申领绑定关系
# pod一直处于pending状态
```

**使用**

```sh
# pod将PVC当作存储卷来使用,集群会通过PVC找到绑定的PVC,并为Pod挂载该卷.
# pod一旦使用PVC绑定PV后,为了保护数据,避免数据丢失问题,PV对象会受到保护,在系统中无法被删除
```

**回收策略**

```sh
# 当用户不在使用其存储卷时,可以从API中将PVC对象删除,从而允许该资源被回收再利.
# PersistentVolume对象的回收策略告诉集群,当其被从申领中释放时如何处理该数据卷.

# Retained	保留
	# 可使用户手动回族资源
	# 当PVC对象被删除时,PV卷仍然存在,对应的数据卷被视为"已释放(released)"
	# 由于卷上人存在之前的数据,该卷不能由其他pod申领.管理员操作后才可再次使用
		# 删除PV对象,与之相关的,位于外部基础设备中的存储资产(AWS,GCE PD, Azure Disk)在PV删除后任然存在
		# 需要手动清除关联的存储资产,如果希望重用该存储资产,可以基于存储资产重新定义PV卷对象
		
# Recycled	回收
	# 已被废弃,建议采用动态制备
	# 如果下层卷插件支持,回收策略会在卷上执行一些基本擦除(rm -rf /tehvolume/*)操作,之后允许该卷重新用户PVC申领

# Deleted	删除
	# 删除动作会在PV对象从kubernets中移除,同时也会从外部基础设施中移除关联的存储资产.
	# 动态制备的卷会集成其StorageClass中设置的回收策略,该策略默认为Delete.
	# 管理原需要根据用户期望来配置StorageClass;否则PV卷被创建之后必须要被编辑或修补
```

##### PV(PersistenVolume)

**状态**

```sh
# Avalable	空闲,未被绑定
# Bound		已经被PVC绑定
# Released	PVC被删除,资源已 回收,但是PV未被重新使用
# Failed	自动回收失败
```



```yaml
# pv-nfs.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv0001
spec:
  capacity:      # 容量配置
    storage: 5Gi # pv 的容量
  volumeMode: Filesystem # 存储类型为文件系统
  accessModes: # 访问模式：ReadWriteOnce  只能被一个使用、ReadWriteMany、ReadOnlyMany
    - ReadWriteMany # 可被单节点独写
  persistentVolumeReclaimPolicy: Retain # 回收策略 Retain  Delete  Recycle
  storageClassName: slow # 创建 PV 的存储类名，需要与 pvc 的相同
  mountOptions: # 加载配置
    - hard
    - nfsvers=4.1
  nfs: # 连接到 nfs
    path: /home/nfs/rw/test-pv # 存储路径
    server: 192.168.28.121 # nfs 服务地址


```

```shell
kubectl create -f pv-nfs.yaml

kubectl get pv
```





##### PVC

pvc 与 pv 绑定

```yaml
# pvc-test.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  accessModes:
    - ReadWriteMany # 权限需要与对应的 pv 相同
  volumeMode: Filesystem
  resources:
    requests:
      storage: 5Gi # 资源可以小于 pv 的，但是不能大于，如果大于就会匹配不到 pv
  storageClassName: slow # 名字需要与对应的 pv 相同
#  selector: # 使用选择器选择对应的 pv
#  #    matchLabels:
#  #      release: "stable"
#  #    matchExpressions:
#  #      - {key: environment, operator: In, values: [dev]}
```



```shell
kubectl create -f pvc-test.yaml

kubectl get pvc
#NAME      STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
#nfs-pvc   Bound    pv0001   5Gi        RWX            slow           10s

```

**pod绑定pvc**

```yaml
# pvc-test-pd.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pvc-pd
spec:
  containers:
  - image: nginx
    name: nginx-volume
    volumeMounts:
    - mountPath: /usr/share/nginx/html # 挂载到容器的哪个目录
      name: test-volume # 挂载哪个 volume
  volumes:
  - name: test-volume
    persistentVolumeClaim:      # 关联pvc
      claimName: nfs-pvc        # 具体关联到哪个pvc


```

```shell
kubectl create -f pvc-test-pd.yaml
kubectl get po
```



```shell
kubectl logs test-pvc-pd
Error from server (BadRequest): container "nginx-volume" in pod "test-pvc-pd" is waiting to start: ContainerCreating

```

##### StorageClasses

**制备器(Provisioner)**

每个StorageClass都有一个制备器(Provisioner),用来决定使用哪个卷插件制备PV

| 卷插件               | 内置制备器 | 配置例子                                                     |
| -------------------- | ---------- | ------------------------------------------------------------ |
| AWSElasticBlockStore | ✓          | [AWS EBS](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#aws-ebs) |
| AzureFile            | ✓          | Azure File                                                   |
| AzureDisk            | ✓          | Azure Disk                                                   |
| CephFS               | -          | -                                                            |
| Cinder               | ✓          | [OpenStack Cinder](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#openstack-cinder) |
| FC                   | -          | -                                                            |
| FlexVolume           | -          | -                                                            |
| Flocker              | ✓          | -                                                            |
| GCEPersistentDisk    | ✓          | [GCE PD](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#gce-pd) |
| Glusterfs            | ✓          | [Glusterfs](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#glusterfs) |
| iSCSI                | -          | -                                                            |
| Quobyte              | ✓          | [Quobyte](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#quobyte) |
| NFS                  | -          | -                                                            |
| RBD                  | ✓          | [Ceph RBD](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#ceph-rbd) |
| VsphereVolume        | ✓          | [vSphere](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#vsphere) |
| PortworxVolume       | ✓          | Portworx Volume                                              |
| ScaleIO              | ✓          | [ScaleIO](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#scaleio) |
| StorageOS            | ✓          | [StorageOS](https://kubernetes.io/zh/docs/concepts/storage/storage-classes/#storageos) |
| Local                | -          | Local                                                        |

```yaml
# nfs-provisioner-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
  namespace: kube-system
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
  namespace: kube-system
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
  namespace: kube-system
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: default
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: kube-system
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: kube-system
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io
```





```yaml
# nfs-provisioner-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
 name: nfs-client-provisioner
 namespace: kube-system
 labels:
   app: nfs-client-provisioner
spec:
 replicas: 1
 strategy:
   type: Recreate
 selector:
   matchLabels:
     app: nfs-client-provisioner
 template:
   metadata:
     labels:
       app: nfs-client-provisioner
   spec:
     serviceAccountName: nfs-client-provisioner
     containers:
       - name: nfs-client-provisioner
         #image: quay.io/external_storage/nfs-client-provisioner:latest 
         # image: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.0
         image: registry.cn-beijing.aliyuncs.com/pylixm/nfs-subdir-external-provisioner:v4.0.0
         imagePullPolicy: IfNotPresent
         volumeMounts:
           - name: nfs-client-root
             mountPath: /persistentvolumes
         env:
           - name: PROVISIONER_NAME
             value: fuseim.pri/ifs
           - name: NFS_SERVER
             value: 192.168.28.121
           - name: NFS_PATH
             value: /home/nfs/rw
     volumes:
       - name: nfs-client-root
         nfs:
           server: 192.168.28.121
           path: /home/nfs/rw
```





```yaml
# nfs-storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-nfs-storage
#  namespace: kube-system
provisioner: fuseim.pri/ifs # 外部制备器提供者，编写为提供者的名称
parameters:
  archiveOnDelete: "false" # 是否存档，false 表示不存档，会删除 oldPath 下面的数据，true 表示存档，会重命名路径
reclaimPolicy: Retain # 回收策略，默认为 Delete 可以配置为 Retain
volumeBindingMode: Immediate # 默认为 Immediate，表示创建 PVC 立即进行绑定，只有 azuredisk 和 AWSelasticblockstore 支持其他值
```





```shell
kubectl apply -f nfs-provisioner-rbac.yaml -n kube-system
kubectl apply -f nfs-provisioner-deployment.yaml -n kube-system
kubectl create -f nfs-storage-class.yaml

# kubectl delete -f nfs-storage-class.yaml
# kubectl delete -f nfs-provisioner-deployment.yaml -n kube-system
# kubectl delete -f nfs-provisioner-rbac.yaml -n kube-system

# 查看创建的pod
kubectl get pod -o wide -n kube-system|grep nfs-client



# 查看pod日志
kubectl logs -f `kubectl get pod -o wide -n kube-system|grep nfs-client|awk '{print $1}'` -n kube-system
```



```shell
# 依次查看
kubectl get sc

kubectl get po -n kube-system | grep nfs

kubectl describe po nfs-client-provisioner-6db95c59c7-mhllw -n kube-system

kubectl logs -f nfs-client-provisioner-7f569f64b6-8m4nw -n kube-system

kubectl describe serviceaccount nfs-client-provisioner -n kube-system

# 如果在CI里面没有特别指定serviceaccount 那么将使用默认账户 system:serviceaccount:dev:default
# 最终的原因就是没有创建 对应 namespaces 的 集群角色绑定clusterrolebinding
#解决办法：
#执行一下命令，创建clusterrolebinding即可
# 解决办法
kubectl create clusterrolebinding gitlab-cluster-admin --clusterrole=cluster-admin --group=system:serviceaccounts --namespace=dev

```

### 高级调度

##### CornJob计划任务

```shell
# linux自带的
crontab -e
```

```yaml
# cron-job.yaml
apiVersion: batch/v1
kind: CronJob	# 定时任务资源
metadata:
  name: corn-job-test	# 定时任务名称
spec:
  concurrencyPolicy: Allow # 并发调度策略：Allow 允许并发调度，Forbid：不允许并发执行，Replace：如果之前的任务还没执行完，就直接执行新的，放弃上一个任务
  failedJobsHistoryLimit: 1 # 保留多少个失败的任务
  successfulJobsHistoryLimit: 3 # 保留多少个成功的任务
  suspend: false # 是否挂起任务，若为 true 则该任务不会执行
#  startingDeadlineSeconds: 30 # 间隔多长时间检测失败的任务并重新执行，时间不能小于 10
  schedule: "* * * * *" # 调度策略
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: busybox
            image: busybox:1.28
            imagePullPolicy: IfNotPresent
            command:
            - /bin/sh
            - -c
            - date; echo Hello from the Kubernetes cluster
          restartPolicy: OnFailure


```

```shell
kubectl get cronjob
kubectl get cj
```

##### 初始化容器

```shell
#在 pod 创建的模板中配置 initContainers 参数：
spec:
  initContainers:
  - image: nginx
    imagePullPolicy: IfNotPresent
    command: ["sh", "-c", "echo 'inited;' >> ~/.init"]
    name: init-test

```

#### 污点和容忍

```shell
# 污点
# 是标注在节点上的.当我们的一个节点上打上污点以后,k8s会认为尽量不要将pod调度该节点上,除非该pod上面表示可以容忍污点,且一个节点可以打多个污点,此时则需要pod容忍所有污点才会被调度节点


# 为节打上污点
kubectl taint node k8s-master key=value:NoSchedule

# ex
kubectl taint no k8s-node2 memory=low:NoSchedule

# 移除污点
kubectl taint node k8s-master key=value:Noschedule-

	# NoSchedule: 不能容忍的pod不能被调度到该节点上,但是已经存在的节点不会被驱逐
	
	# NoExecute: 不能容忍的节点会被立即清除,能容忍且没有配置
		# tolerationSeconds: 设置了则可以一直运行
		# tolerationSeconds: 3600属性,则该pod还能在该节点运行3600秒
	
	
# 查看污点
kubectl describe no k8s-node2 | grep Taints

# 移除master污点
kubectl taint no k8s-master node-role.kubernetes.io/master:NoSchedule-

kubectl taint no k8s-master node-role.kubernetes.io/master:NoExecute

# Master节点
#Taints:             node-role.kubernetes.io/master:NoSchedule


```

```shell
# 容忍
# 是标注在pod上的,当pod被调度时,如果没有配置容忍,则该pod不会被调度到有污点的节点上,只有该pod上标注满足某个节点上的所有污点,则会被调度到这个节点

# pod的sepc下配置容忍
tolerations:
- key: "污点的key"
  value: "污点的value"
  offect: "NoSchedule"
	# Equal: 必须与污点值做匹配,key/value都必须相同
	# Exists: 容忍与污点的比较只比较key,不比较value,不关心value是什么东西,只要key存在,就可以容忍

       
spec:
 tolerations:
 - key: "memory"
   operator: "Equal"
   value: "low"
   effect: "NoSchedule"

```



```yaml
apiVersion: v1
kind: Pod
metadata:
  name: with-affinity-anti-affinity
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values:
            - linux
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: label-1
            operator: In
            values:
            - key-1
      - weight: 50
        preference:
          matchExpressions:
          - key: label-2
            operator: In
            values:
            - key-2
  containers:
  - name: with-node-affinity
    image: registry.k8s.io/pause:2.0
```

##### 亲和性

```shell

kubectl label no k8s-node1 label-1=key-1

kubectl label no k8s-node2 label-2=key-2

kubectl label no k8s-node1 k8s-node1 k8s-node2 topology.kubernetes.io/zone=V --overwrite

kubectl label no k8s-master topology.kubernetes.io/zone=R --overwrite
```

### 身份认证与权限



```shell
kubectl get sa
kubectl get serviceaccount

kubectl get rolebinding --all-namespaces
kubectl get rolebinding -A
```





## 运维管理

### Helm

```shell
# 列出,增加,更新,删除char仓库
helm repo list

# 使用关键字搜索char
helm search
helm search hub redis



helm pull

helm create

helm dependency

helm install
helm list
# helm list -n ingress-nginx

helm lint
helm package
helm rollback
helm uninstall
helm upgrade
```



```shell
# 查看默认仓库
helm repo list

# 修改helm源
# 添加仓库
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add aliyun https://apphub.aliyuncs.com/stable
helm repo add azure http://mirror.azure.cn/kubernetes/charts



```





```shell
# 搜索redis
helm search repo redis

# 拉取redis
helm pull bitnami/redis


kubectl create ns redis



helm install redis ./redis/ -n redis
# helm uninstall redis -n redis

# 获取redis命名空间下的所有资源
kubectl get all -n redis

kubectl get pvc -n redis



```



```shell
kubectl get all -n redis

kubectl describe pod/redis-master-0 -n redis
# Warning  FailedScheduling  14s (x4 over 3m26s)  default-scheduler  0/3 nodes are available: 3 pod has unbound immediate PersistentVolumeClaims.
# 3个节点都可以,调度失败,没有绑定到PVC

kubectl get pvc -n redis

kubectl describe pvc redis-data-redis-master-0 -n redis

# 排错
出现pending

# 查看是否有pvc卷
kubectl get pvc -n redis



# 查找nfs的sc的状态
kubectl get po -n kube-system| grep nfs

# 查找是否有sc
kubectl get sc
```



```shell
kubectl exec -it redis-master-0 -n redis -- bash
```



**更新回滚**

```shell
# 想要升级chart可以修改本地的chart配置并执行
helm upgrade [RELEASE] [CHART] [flags]
helm upgrade redis ./redis -n redis

#查看当前运行的chart的release版本,
helm ls -n redis

# 回滚历史版本
helm rollback <RELEASE> [REVISION] [flags]

# 查看历史
helm history redis -n redis

# 回退到上一版
helm rollback redis -n redis

# 回退到指定版本
helm rollback redis 3 -n redis


```





```shell
helm list -n redis
helm delete redis -n redis



kubectl get pvc -n redis

kubectl get pv -n redis

kubectl delete pvc redis-data-redis-master-0 redis-data-redis-replicas-0 redis-data-redis-replicas-1 redis-data-redis-replicas-2 -n redis

kubectl delete pv pvc-0fcea3d6-fcb0-401c-9b6d-38a79bd631a1 pvc-13d731f9-1ba8-45c9-ae9c-e4e32c43b6c2 pvc-3f34d4e1-c356-4b40-a636-f296fd07971b pvc-d1cd23aa-291f-423d-80dc-4cba17f2d205 -n redis
```





### k8s集群监控(Iaas)

#### 监控方案

##### Heapster

```sh
Heapster是容器集群监控和性能分析工具,天然支持kubernetes和CoreOS
kubernetes有个出名的监控agent---cAdvisor.在每个kuhbernetes node上都会运行cAdvisor,它会手机本机以及容器的监控数据(cpu,memory,filesystem,network,uptime).
在较新版本中,k8s已经降cAdvisor功能集成到kubelet组件中,每个Node节点可以直接web访问
```

##### Weave Scope

```sh
监控kubernetes集群中的一系列资源的状态,资源使用情况,应用拓扑,scale,还可以直接通过浏览器进入容器内部调试等,其提供的功能包括:
	交互式拓扑界面
	图形模式和表格模式
	过滤功能
	搜索功能
	实时度量
	容器排错
	插件扩展
```





##### Prometheus





### Prometheus监控k8s

#### 自定义监控

##### 创建configMap   

```yaml
# 创建 prometheus-config.yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s 			# 拉取时间
      evaluation_interval: 15s		# 间隔时间
    scrape_configs:					# 任务配置
    
      - job_name: 'prometheus'		# 任务名称
        static_configs:				
        - targets: ['localhost:9090']	# 关联
        
      - job_name: 'kubernetes-nodes'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: node

      - job_name: 'kubernetes-service'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: service

      - job_name: 'kubernetes-endpoints'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: endpoints

      - job_name: 'kubernetes-ingress'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: ingress
        


      - job_name: 'kubernetes-pods'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: pod
 
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          target_label: __address__
        - action: labelmap
          regex: __meta_kubernetes_pod_label_(.+)
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_pod_name]
          action: replace
          target_label: kubernetes_pod_name


      # 往 prometheus-config.yml 中追加如下配置
      - job_name: 'kubernetes-kubelet'	# 对与kubectl的监控
        scheme: https					# 协议
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: node					# 使用node角色
        relabel_configs:
        - action: labelmap				# 动作 做什么
          regex: __meta_kubernetes_node_label_(.+)	# 匹配规则
        - target_label: __address__		# 替换地址
          replacement: kubernetes.default.svc:443	# 匹配后替换
        - source_labels: [__meta_kubernetes_node_name]
          regex: (.+)
          target_label: __metrics_path__
          replacement: /api/v1/nodes/${1}/proxy/metrics

      
      
      # 修改配置文件，增加如下内容，并更新服务
      - job_name: 'kubernetes-cadvisor'
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: node
        relabel_configs:
        - target_label: __address__
          replacement: kubernetes.default.svc:443
        - source_labels: [__meta_kubernetes_node_name]
          regex: (.+)
          target_label: __metrics_path__
          replacement: /api/v1/nodes/${1}/proxy/metrics/cadvisor
        - action: labelmap
          regex: __meta_kubernetes_node_label_(.+)
```

```shell
# 创建 configmap
kubectl create -f prometheus-config.yml
```



##### 配置访问权限 prometheus-rbac-setup.yml

```yaml
# 创建 prometheus-rbac-setup.yml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups:
  - extensions
  resources:
  - ingresses
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding		# 角色绑定
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: default
```

```shell
# 创建资源对象
kubectl create -f prometheus-rbac-setup.yml

# 修改 prometheus-deploy.yml 配置文件
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus
      serviceAccount: prometheus

# 升级 prometheus-deployment
kubectl apply -f prometheus-deployment.yml

# 查看 pod
kubectl get pods -l app=prometheus

# 查看 serviceaccount 认证证书
kubectl exec -it <pod name> -- ls /var/run/secrets/kubernetes.io/serviceaccount/

```



##### 部署prometheus   prometheus-deployment.yml

```yaml
# 创建 prometheus-deployment.yml
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  labels:
    name: prometheus
spec:
  ports:
  - name: prometheus
    protocol: TCP
    port: 9090
    targetPort: 9090
  selector:
    app: prometheus
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    name: prometheus
  name: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus	# 分配角色
      serviceAccount: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:v2.2.1
        command:
        - "/bin/prometheus"
        args:
        - "--config.file=/etc/prometheus/prometheus.yml"
        ports:
        - containerPort: 9090
          protocol: TCP
        volumeMounts:
        - mountPath: "/etc/prometheus"
          name: prometheus-config
        - mountPath: "/etc/localtime"
          name: timezone
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
      - name: timezone				# 时间同步
        hostPath:
          path: /usr/share/zoneinfo/Asia/Shanghai

```

```shell
# 创建部署对象
kubectl create -f prometheus-deployment.yml

# 查看是否在运行中
kubectl get pods -l app=prometheus

# 获取服务信息
kubectl get svc -l name=prometheus

# 通过 http://节点ip:端口 进行访问

```



##### 服务发现配置

```yaml
# 配置 job，帮助 prometheus 找到所有节点信息，修改 prometheus-config.yml 增加为如下内容
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
        - targets: ['localhost:9090']
      - job_name: 'kubernetes-nodes'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: node

      - job_name: 'kubernetes-service'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: service

      - job_name: 'kubernetes-endpoints'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: endpoints

      - job_name: 'kubernetes-ingress'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: ingress

      - job_name: 'kubernetes-pods'
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: pod
# 升级配置
kubectl apply -f prometheus-config.yml

# 获取 prometheus pod
kubectl get pods -l app=prometheus

# 删除 pod
kubectl delete pods <pod name>

# 查看 pod 状态
kubectl get pods

# 重新访问 ui 界面

```

##### 系统时间同步

```shell
# 查看系统时间
date

# 同步网络时间
ntpdate cn.pool.ntp.org
```

##### 监控k8s集群

###### 从 kubelet 获取节点容器资源使用情况

```shell
 # 修改配置文件，增加如下内容，并更新服务
      - job_name: 'kubernetes-cadvisor'
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        kubernetes_sd_configs:
        - role: node
        relabel_configs:
        - target_label: __address__
          replacement: kubernetes.default.svc:443
        - source_labels: [__meta_kubernetes_node_name]
          regex: (.+)
          target_label: __metrics_path__
          replacement: /api/v1/nodes/${1}/proxy/metrics/cadvisor
        - action: labelmap
          regex: __meta_kubernetes_node_label_(.+)
```



###### Exporter监控资源使用情况 node-exporter-daemonset.yml

```shell
# 创建 node-exporter-daemonset.yml 文件
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: 'true'
        prometheus.io/port: '9100'
        prometheus.io/path: 'metrics'
      labels:
        app: node-exporter
      name: node-exporter
    spec:
      containers:
      - image: prom/node-exporter
        imagePullPolicy: IfNotPresent
        name: node-exporter
        ports:
        - containerPort: 9100
          hostPort: 9100
          name: scrape
      hostNetwork: true
      hostPID: true

```



```shell

# 创建 daemonset
kubectl create -f node-exporter-daemonset.yml

# 查看 daemonset 运行状态
kubectl get daemonsets -l app=node-exporter

# 查看 pod 状态
kubectl get pods -l app=node-exporter

# 修改配置文件，增加监控采集任务
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          target_label: __address__
        - action: labelmap
          regex: __meta_kubernetes_pod_label_(.+)
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_pod_name]
          action: replace
          target_label: kubernetes_pod_name

# 通过监控 apiserver 来监控所有对应的入口请求，增加 api-server 监控配置
      - job_name: 'kubernetes-apiservers'
        kubernetes_sd_configs:
        - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
        - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
          action: keep
          regex: default;kubernetes;https
        - target_label: __address__
          replacement: kubernetes.default.svc:443
```

###### Ingress和Service进行网络探测  blackbox-exporter.yaml

```shell
# 创建 blackbox-exporter.yaml 进行网络探测
apiVersion: v1
kind: Service
metadata:
  labels:
    app: blackbox-exporter
  name: blackbox-exporter
spec:
  ports:
  - name: blackbox
    port: 9115
    protocol: TCP
  selector:
    app: blackbox-exporter
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: blackbox-exporter
  name: blackbox-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blackbox-exporter
  template:
    metadata:
      labels:
        app: blackbox-exporter
    spec:
      containers:
      - image: prom/blackbox-exporter
        imagePullPolicy: IfNotPresent
        name: blackbox-exporter

# 创建资源对象
kubectl -f blackbox-exporter.yaml

# 配置监控采集所有 service/ingress 信息，加入配置到配置文件
    - job_name: 'kubernetes-services'
      metrics_path: /probe
      params:
        module: [http_2xx]
      kubernetes_sd_configs:
      - role: service
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_probe]
        action: keep
        regex: true
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: blackbox-exporter.default.svc.cluster.local:9115
      - source_labels: [__param_target]
        target_label: instance
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_service_name]
        target_label: kubernetes_name

      - job_name: 'kubernetes-ingresses'
        metrics_path: /probe
        params:
          module: [http_2xx]
        kubernetes_sd_configs:
        - role: ingress
        relabel_configs:
        - source_labels: [__meta_kubernetes_ingress_annotation_prometheus_io_probe]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_ingress_scheme,__address__,__meta_kubernetes_ingress_path]
          regex: (.+);(.+);(.+)
          replacement: ${1}://${2}${3}
          target_label: __param_target
        - target_label: __address__
          replacement: blackbox-exporter.default.svc.cluster.local:9115
        - source_labels: [__param_target]
          target_label: instance
        - action: labelmap
          regex: __meta_kubernetes_ingress_label_(.+)
        - source_labels: [__meta_kubernetes_namespace]
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_ingress_name]
          target_label: kubernetes_name
```

##### Grafana可视化

###### 部署Grafana   grafana-statefulset.yml

```yaml
# grafana-statefulset.yml
apiVersion: apps/v1
# kind: Deployment
kind: StatefulSet
metadata:
  name: grafana-core
  namespace: kube-system
  labels:
    app: grafana
    component: core
spec:
  selector:
    matchLabels:
      app: grafana
  replicas: 1
  template:
    metadata:
      labels:
        app: grafana
        component: core
    spec:
      containers:
      - image: grafana/grafana:6.5.3
        name: grafana-core
        imagePullPolicy: IfNotPresent
        env:
          # The following env variables set up basic auth twith the default admin user and admin password.
          - name: GF_AUTH_BASIC_ENABLED
            value: "true"
          - name: GF_AUTH_ANONYMOUS_ENABLED
            value: "false"
          # - name: GF_AUTH_ANONYMOUS_ORG_ROLE
          #   value: Admin
          # does not really work, because of template variables in exported dashboards:
          # - name: GF_DASHBOARDS_JSON_ENABLED
          #   value: "true"
        readinessProbe:
          httpGet:
            path: /login
            port: 3000
          # initialDelaySeconds: 30
          # timeoutSeconds: 1
        volumeMounts:
        - name: grafana-persistent-storage
          mountPath: /var
      volumes:
      - name: grafana-persistent-storage
        hostPath:
          path: /data/devops/grafana
          type: Directory

```

##### Grafana service grafana-service.yml

```yaml
# grafana-service.yml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: kube-system
  labels:
    app: grafana
    component: core
spec:
  type: NodePort
  ports:
    - port: 3000
      nodePort: 30011
  selector:
    app: grafana
    component: core
```

##### kube-monitoring.yml

```yaml
prometheus/kube-monitoring.yml
apiVersion: v1
kind: Namespace
metadata:
  name: kube-monitoring
```



```shell
kubectl apply -f prometheus/kube-monitoring.yml

kubectl apply -f ./prometheus/

kubectl delete -f prometheus/
```



### ELK日志管理



### Kubenetes可视化界面



#### kuberneter-dashboard

```yaml

```



```yaml

```

```shell
# 下载官方部署配置文件
wget https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# 修改属性
kind: Service
apiVersion: v1
metadata:
  labels:
    k8s-app: kubernetes-dashboard
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
spec:
  type: NodePort   #新增
  ports:
    - port: 443
      targetPort: 8443
  selector:
    k8s-app: kubernetes-dashboard

# 创建资源
kubectl apply -f recommend.yaml

# 查看资源是否已经就绪
kubectl get all -n kubernetes-dashboard -o wide

# 访问测试
https://节点ip:端口




kubectl get all -n kubernetes-dashboard


kubectl get secret -n kubernetes-dashboard

# 获取tonken
kubectl describe secret kubernetes-dashboard-token-8hpfg -n kubernetes-dashboard
```





#### kubeshpere

```shell
# 在所有节点安装 iSCSI 协议客户端（OpenEBS 需要该协议提供存储支持）
yum install iscsi-initiator-utils -y
# 设置开机启动
systemctl enable --now iscsid
# 启动服务
systemctl start iscsid
# 查看服务状态
systemctl status iscsid

# 安装 OpenEBS 
kubectl apply -f https://openebs.github.io/charts/openebs-operator.yaml
kubectl apply -f openebs-operator.yaml

# 查看状态（下载镜像可能需要一些时间）
kubectl get all -n openebs


# 在主节点创建本地 storage class
kubectl apply -f default-storage-class.yaml



# 安装资源
kubectl apply -f https://github.com/kubesphere/ks-installer/releases/download/v3.3.1/kubesphere-installer.yaml
kubectl apply -f https://github.com/kubesphere/ks-installer/releases/download/v3.3.1/cluster-configuration.yaml

# 检查安装日志
kubectl logs -n kubesphere-system $(kubectl get pod -n kubesphere-system -l 'app in (ks-install, ks-installer)' -o jsonpath='{.items[0].metadata.name}') -f

# 查看端口
kubectl get svc/ks-console -n kubesphere-system

# 默认端口是 30880，如果是云服务商，或开启了防火墙，记得要开放该端口

# 登录控制台访问，账号密码：admin/P@88w0rd



kubectl get scs
kubectl apply -f kubesphere-installer.yaml
kubectl apply -f kubesphere-ingress.yaml
kubectl apply -f cluster-configuration.yaml

```





### Devops环境搭建

#### gitlab

```shell
# 下载安装包
https://mirrors.tuna.tsinghua.edu.cn/gitlab-ce/yum/el7/gitlab-ce-15.9.1-ce.0.el7.x86_64.rpm

# 安装
rpm -i gitlab-ce-15.9.1-ce.0.el7.x86_64.rpm

# 编辑配置文件
vim /etc/gitlab/gitlab.rb

# 修改 external_url 访问路径 http://<ip>:<port>
# 其他配置修改如下
# 时区
gitlab_rails['time_zone'] = 'Asia/Shanghai'
# 减少数据库并发数
puma['worker_processes'] = 1
unicorn['worker_timeout'] = 90

# 减少sidekiq并发数
sidekiq['max_concurrency'] = 1
sidekiq['min_concurrency'] = 1
# 减少数据库缓存
postgresql['shared_buffers'] = "128MB"
postgresql['max_worker_processes'] = 4
# 关闭promethus监控
prometheus_monitoring['enable'] = false

# 更新配置并重启
gitlab-ctl reconfigure
gitlab-ctl restart


# 用户 root
# 获取默认密码
cat /etc/gitlab/initial_root_password

# 修改系统配置
# 点击左上角三横 > Admin
# 关闭头像
# Settings > General > Account and limit > 取消 Gravatar enabled > Save changes

# 关闭用户注册功能
# Settings > General > Sign-up restrictions > 取消 Sign-up enabled > Save changes

# 开启 webhook 外部访问
# Settings > Network > Outbound requests > Allow requests to the local network from web hooks and services 勾选

# 设置语言为中文（全局）
# Settings > Preferences > Localization > Default language > 选择简体中文 > Save changes

# 设置当前用户语言为中文
# 右上角用户头像 > Preferences > Localization > Language > 选择简体中文 > Save changes



# 删除gitlab
gitlab-ctl stop

rpm -e gitlab-ce

ps aux | grep gitlab

kill -9 20622

find / -name gitlab | xargs rm -rf
```



#### harbor

```shell
# 下载docker-compose 至/usr/local/bin/docker-compose目录
curl -L "https://github.com/docker/compose/releases/download/v2.2.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# github下载地址 如果下载不下来可能是被墙了 可以直接去github下载
https://github.com/docker/compose/releases/download/v2.18.1/docker-compose-linux-x86_64


# 下载到 /usr/local/bin 改名为docker-compose
cd /usr/local/bin
mv docker-compose-linux-x86_64 docker-compose
# 赋予权限 
chmod a+x docker-compose

# 因为直接在/usr/local/bin系统变量目录 
$PATH 
 
# 检查是否安装成功   tip:从2023年1月起，官方取消了docker-compose --version
docker compose version


# 下载harbor
wget https://github.com/goharbor/harbor/releases/download/v2.5.0/harbor-offline-installer-v2.5.0.tgz

# 解压
tar -zxvf harbor-offline-installer-v2.5.0.tgz
cd harbor-offline

# vim harbor.yml
hostname: 192.168.28.122
http:
	port: 8858
harbor_admin_password: 200212..


# 注释掉https 和 port

# 登录 用户 admin

# 添加信任仓库
vim /etc/docker/daemon
"insecure-registries": ["192.168.28.122:8858"]
"exec-opts": ["native.cgroupdriver=systemd"]

systemctl daemon-reload 
systemctl restart docker

```

#### sonarqube

###### nfs

```shell
# 安装 nfs
yum install nfs-utils -y

# 启动 nfs
systemctl start nfs-server
# 开机自启
systemctl status nfs-server

df -h

# 查看 nfs 版本
cat /proc/fs/nfsd/versions

# 创建共享目录
mkdir -p /data/nfs
cd /data/nfs
mkdir rw
mkdir ro

# 设置共享目录 export
vim /etc/exports
/home/nfs/rw 192.168.28.0/24(rw,sync,no_subtree_check,no_root_squash)
/home/nfs/ro 192.168.28.0/24(ro,sync,no_subtree_check,no_root_squash)

# 重新加载
exportfs -f
systemctl reload nfs-server

# 到其他测试节点安装 nfs-utils 并加载测试
mkdir -p /mnt/nfs/rw
mount -t nfs 192.168.28.121:/home/nfs/rw /mnt/nfs/rw
mount -t nfs 192.168.28.121:/home/nfs/ro /mnt/nfs/ro

unmount
```



```yaml
# nfs-provisioner-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
  namespace: kube-system
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
  namespace: kube-system
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
  namespace: kube-system
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    namespace: default
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: kube-system
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  namespace: kube-system
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io
```

```yaml
# nfs-storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-nfs-storage
#  namespace: kube-system
provisioner: fuseim.pri/ifs # 外部制备器提供者，编写为提供者的名称
parameters:
  archiveOnDelete: "false" # 是否存档，false 表示不存档，会删除 oldPath 下面的数据，true 表示存档，会重命名路径
reclaimPolicy: Retain # 回收策略，默认为 Delete 可以配置为 Retain
volumeBindingMode: Immediate # 默认为 Immediate，表示创建 PVC 立即进行绑定，只有 azuredisk 和 AWSelasticblockstore 支持其他值
```

```yaml
# nfs-provisioner-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
 name: nfs-client-provisioner
 namespace: kube-system
 labels:
   app: nfs-client-provisioner
spec:
 replicas: 1
 strategy:
   type: Recreate
 selector:
   matchLabels:
     app: nfs-client-provisioner
 template:
   metadata:
     labels:
       app: nfs-client-provisioner
   spec:
     serviceAccountName: nfs-client-provisioner
     containers:
       - name: nfs-client-provisioner
         #image: quay.io/external_storage/nfs-client-provisioner:latest \
         #image: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.0
         image: registry.cn-beijing.aliyuncs.com/pylixm/nfs-subdir-external-provisioner:v4.0.0
         imagePullPolicy: IfNotPresent
         volumeMounts:
           - name: nfs-client-root
             mountPath: /persistentvolumes
         env:
           - name: PROVISIONER_NAME
             value: fuseim.pri/ifs
           - name: NFS_SERVER
             value: 192.168.28.121
           - name: NFS_PATH
             value: /home/nfs/rw
     volumes:
       - name: nfs-client-root
         nfs:
           server: 192.168.28.121
           path: /home/nfs/rw
```



```shell

# 重新加载nfs
systemctl daemon-reload
systemctl restart rpcbind.socket
systemctl start nfs


# 检查
kubectl get po -n kube-system | grep nfs
kubectl get sc -n kube-syste
```





```yaml
# pgsql.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: kube-devops
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: "managed-nfs-storage"
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-sonar
  namespace: kube-devops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-sonar
  template:
    metadata:
      labels:
        app: postgres-sonar
    spec:
      containers:
      - name: postgres-sonar
        image: postgres:14.2
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: "sonarDB"
        - name: POSTGRES_USER
          value: "sonarUser"
        - name: POSTGRES_PASSWORD
          value: "123456"
        volumeMounts:
          - name: data
            mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-data
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-sonar
  namespace: kube-devops
  labels:
    app: postgres-sonar
spec:
  type: NodePort
  ports:
  - name: postgres-sonar
    port: 5432
    targetPort: 5432
    protocol: TCP
  selector:
    app: postgres-sonar

```



```yaml
# sonarqube.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sonarqube-data
  namespace: kube-devops
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: "managed-nfs-storage"
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube
  namespace: kube-devops
  labels:
    app: sonarqube
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube
  template:
    metadata:
      labels:
        app: sonarqube
    spec:
      initContainers:
      - name: init-sysctl
        image: busybox:1.28.4
        command: ["sysctl", "-w", "vm.max_map_count=262144"]		# 需要大于这个内存不然运行不成功
        securityContext:
          privileged: true
      containers:
      - name: sonarqube
        image: sonarqube
        ports:
        - containerPort: 9000
        env:
        - name: SONARQUBE_JDBC_USERNAME
          value: "sonarUser"
        - name: SONARQUBE_JDBC_PASSWORD
          value: "123456"
        - name: SONARQUBE_JDBC_URL
          value: "jdbc:postgresql://postgres-sonar:5432/sonarDB"
        livenessProbe:
          httpGet:
            path: /sessions/new
            port: 9000
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /sessions/new
            port: 9000
          initialDelaySeconds: 60
          periodSeconds: 30
          failureThreshold: 6
        volumeMounts:
        - mountPath: /opt/sonarqube/conf
          name: data
        - mountPath: /opt/sonarqube/data
          name: data
        - mountPath: /opt/sonarqube/extensions
          name: data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: sonarqube-data
---
apiVersion: v1
kind: Service
metadata:
  name: sonarqube
  namespace: kube-devops
  labels:
    app: sonarqube
spec:
  type: NodePort
  ports:
  - name: sonarqube
    port: 9000
    targetPort: 9000
    protocol: TCP
  selector:
    app: sonarqube

```



```shell
kubectl create ns kube-devops
kubectl apply -f pgsql.yaml  -f sonarqube.yaml
kubectl get all -n kube-devops

# 查看日志
kubectl logs -f pod/sonarqube-58669db48f-t6g8l -n kube-devops
# 以下表示运行成功
SonarQube is up

# admin admin
```

#### jenkins

###### 配置docker 私人仓库

```shell
# 登录 用户 admin

# 添加信任仓库
vim /etc/docker/daemon
{
  "registry-mirrors": ["https://55fwm9g2.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "insecure-registries": ["registry.cn-hangzhou.aliyuncs.com", "192.168.28.122:8858"]

}

systemctl daemon-reload 
systemctl restart docker
```

###### 构建jenkins-maven

```dockerfile
FROM jenkins/jenkins:2.392-jdk11
ADD ./apache-maven-3.9.0-bin.tar.gz /usr/local/
ADD ./sonar-scanner-cli-4.8.0.2856-linux.zip /usr/local/

USER root

WORKDIR /usr/local/
RUN unzip sonar-scanner-cli-4.8.0.2856-linux.zip
RUN mv sonar-scanner-4.8.0.2856-linux sonar-scanner-cli
RUN ln -s /usr/local/sonar-scanner-cli/bin/sonar-scanner /usr/bin/sonar-scanner

ENV MAVEN_HOME=/usr/local/apache-maven-3.9.0
ENV PATH=$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH

RUN echo "jenkins ALL=NOPASSWD: ALL" >> /etc/sudoers
USER jenkins




# 制作镜像上传到仓库
docker login --username=toweron registry.cn-hangzhou.aliyuncs.com
$ docker tag [ImageId] registry.cn-hangzhou.aliyuncs.com/toweron/jenkins-maven:[镜像版本号]
$ docker push registry.cn-hangzhou.aliyuncs.com/toweron/jenkins-maven:[镜像版本号]

# 构建镜像
docker build -t registry.cn-hangzhou.aliyuncs.com/toweron/jenkins-maven:v1 .
docker push registry.cn-hangzhou.aliyuncs.com/toweron/jenkins-maven:v1


# 配置阿里仓库secret
kubectl create secret docker-registry aliyum-secret --docker-server=registry.cn-hangzhou.aliyuncs.com --docker-username=toweron --docker-password=200212.. -n kube-devops



secret
echo 1446137304@qq.com > ./username
echo 200212.. > password
kubectl create secret generic git-user-pass --from-file=./username --from-file=./password -n kube-devops
```

#### 构建k8s-jenkins

```yaml
# jenkins-serviceAccount.yaml  账户权限配置
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-admin
  namespace: kube-devops
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: jenkins-admin
  namespace: kube-devops
```

```yaml
# jenkins-pvc.yaml  数据卷
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: kube-devops
spec:
  storageClassName: managed-nfs-storage
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
```

```yaml
# jenkins-configmap.yaml  配置管理 配置了maven仓库配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: mvn-settings
  namespace: kube-devops
  labels:
    app: jenkins-server
data:
  settings.xml: |-
    <?xml version="1.0" encoding="UTF-8"?>
    <settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">
        <localRepository>/var/jenkins_home/repository</localRepository>
        <servers>
                <server>
                        <id>releases</id>
                        <username>admin</username>
                        <password>200212..</password>
                </server>
                <server>
                        <id>snapshots</id>
                        <username>admin</username>
                        <password>200212..</password>
                </server>
        </servers>

        <mirrors>
                <mirror>
                        <id>releases</id>
                        <name>nexus maven</name>
                        <mirrorOf>*</mirrorOf>
                        <url>http://maven.aliyun.com/nexus/content/groups/public/</url>
                </mirror>
        </mirrors>

        <pluginGroups>
                <pluginGroup>org.sonarsource.scanner.maven</pluginGroup>
        </pluginGroups>
        <profiles>
                <profile>
                        <id>releases</id>
                        <activation>
                                <activeByDefault>true</activeByDefault>
                                <jdk>1.8</jdk>
                        </activation>
                        <properties>
                                <sonar.host.url>http://sonarqube:9000</sonar.host.url>
                        </properties>

                        <repositories>
                                <repository>
                                        <id>repository</id>
                                        <name>Nexus Repository</name>
                                        <url>http://maven.aliyun.com/nexus/content/groups/public</url>
                                        <releases>
                                                <enable>true</enable>
                                        </releases>
                                        <snapshots>
                                                <enable>true</enable>
                                        </snapshots>
                                </repository>
                        </repositories>
                </profile>
        </profiles>
    </settings>
```

```yaml
# jenkins-service.yaml  网络配置
apiVersion: v1
kind: Service
metadata:
  name: jenkins-service
  namespace: kube-devops
  annotations:
      prometheus.io/scrape: 'true'
      prometheus.io/path:   /
      prometheus.io/port:   '8080'
spec:
  selector:
    app: jenkins-server
  type: NodePort
  ports:
    - port: 8080
      targetPort: 8080
    - port: 50000
      protocol: TCP
      targetPort: 50000
```

```yaml
# jenkins-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: kube-devops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins-server
  template:
    metadata:
      labels:
        app: jenkins-server
    spec:
      serviceAccountName: jenkins-admin
      imagePullSecrets:
        - name: aliyum-secret # harbor 访问   或者看情况修改成自己阿里云的容器仓库
      containers:
        - name: jenkins
          #image: 192.168.113.122:8858/library/jenkins-maven:jdk-11
          image: registry.cn-hangzhou.aliyuncs.com/toweron/jenkins-maven:v1
#          image: registry.cn-hangzhou.aliyuncs.com/toweron/jenkins-maven:v1
          imagePullPolicy: IfNotPresent
          securityContext:
            privileged: true
            runAsUser: 0 # 使用 root 用户运行容器
          resources:
            limits:
              memory: "2Gi"
              cpu: "1000m"
            requests:
              memory: "500Mi"
              cpu: "500m"
          ports:
            - name: httpport
              containerPort: 8080
            - name: jnlpport
              containerPort: 50000
          livenessProbe:
            httpGet:
              path: "/login"
              port: 8080
            initialDelaySeconds: 90
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: "/login"
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          volumeMounts:
            - name: jenkins-data
              mountPath: /var/jenkins_home
            - name: docker
              mountPath: /run/docker.sock
            - name: docker-home
              mountPath: /usr/bin/docker
            - name: mvn-setting
              mountPath: /usr/local/apache-maven-3.9.0/conf/settings.xml
              subPath: settings.xml
            - name: daemon
              mountPath: /etc/docker/daemon.json
              subPath: daemon.json
            - name: kubectl
              mountPath: /usr/bin/kubectl
      volumes:
        - name: kubectl
          hostPath:
            path: /usr/bin/kubectl
        - name: jenkins-data
          persistentVolumeClaim:
              claimName: jenkins-pvc
        - name: docker
          hostPath:
            path: /run/docker.sock # 将主机的 docker 映射到容器中
        - name: docker-home
          hostPath:
            path: /usr/bin/docker
        - name: mvn-setting
          configMap:
            name: mvn-settings
            items:
            - key: settings.xml
              path: settings.xml
        - name: daemon
          hostPath:
            path: /etc/docker/
```

###### 开始构建jenkins

```shell
# 进入 jenkins 目录，安装 jenkins
kubectl apply -f manifests/

# 查看是否运行成功
kubectl get po -n kube-devops


# 查看 service 端口，通过浏览器访问
kubectl get svc -n kube-devops


# 查看容器日志，获取默认密码
kubectl logs -f pod名称 -n kube-devops


# 同步cinfigmap配置  更新配置
kubectl rollout restart deployment jenkins -n kube-devop
kubectl rollout restart deployment [deployment名]
```

###### 安装插件

```shell
# 构建授权tokne
Build Authorization Token Root

# 仓库拉取插件
gitlabe 或  gitee

# 代码质量审查工具
sonarQube Scanner

# 修改sonarQuber 配置
在 Dashboard > 系统管理 > Configure System 下面配置 SonarQube servers

Name：sonarqube # 注意这个名字要在 Jenkinsfile 中用到
Server URL：http://sonarqube:9000
Server authentication token：创建 credentials 配置为从 sonarqube 中得到的 token

进入系统管理 > 全局工具配置 > SonarQube Scanner > Add SonarQube Scanner
Name：sonarqube-scanner
自动安装：取消勾选
SONAR_RUNNER_HOME：/usr/local/sonar-scanner-cli


# 节点参数配置
Node and Label parameter

# jenkins + k8s 环境
Kubernetes



配置 k8s 集群
名称：kubernetes
点击 Kubernetes Cloud details 继续配置
Kubernetes 地址：
	如果 jenkins 是运行在 k8s 容器中，直接配置服务名即可
		https://kubernetes.default
	如果 jenkins 部署在外部，那么则不仅要配置外部访问 ip 以及 apiserver 的端口（6443），还需要配置服务证书
Jenkins 地址：
	如果部署在 k8s 集群内部：http://jenkins-service.kube-devops
	如果在外部：http://192.168.113.120:32479（换成你们自己的）

配置完成后保存即可


# 用户加载外部配置文件  例如maven的settings.xml 或者 k8s的kubeconfig等
Config File Provider

# git参数插件,进行项目参数化构建时使用
Git Paramenter
```

###### jenkins系统设置

- Credentials 证书配置  全局凭证

  | ID                       | 名称                                       | 类型                   | 描述               |
  | ------------------------ | ------------------------------------------ | ---------------------- | ------------------ |
  | sonarqube-token          | sonarqube认证token                         | Secret text            | sonarqube认证token |
  | gitee-user-pass          | 1446137304@qq.com/****** (gitee用户名密码) | Username with password | gitee用户名密码    |
  | aliyum-docker-user-pass  | toweron/****** (阿里云私人镜像仓库)        | Username with password | 阿里云私人镜像仓库 |
  | gitee-api-token          | Gitee API 令牌 (git私人令牌)               | Gitee API 令牌         | git私人令牌        |
  | k8s-jenkins-admin-secret | k8s连接                                    | Secret text            | k8s连接            |

  ```sh
  sonarqube-token
  # 在sonarqube界面 > 头像 > administrator > 安全 > 生成令牌
  
  gitee-user-pass
  # gitee的用户名和密码
  
  aliyum-docker-user-pass
  # 阿里云的ARC容器服务  此为我的阿里云账号密码
  
  gitee-api-token
  # gitee个人中心 > 私人令牌 > 填写描述,提交 > 复制结果
  
  k8s-jenkins-admin-secret
  # get sa -n kube-devops  获取 serviceAccount
  # kubectl describe sc jenkins-admin -n kube-devops # 查看绑定的secret
  # kubectl describe sa jenkins-admin -n kube-devops	# 复制token
  
  ```

- 系统配置

  ```sh
  # SonarQube servers
  Name: sonarqube
  Server URL: http://sonarqube.kube-devops:9000
  Server authentication token: sonarqube认证token  # 选择这个
  ```

  ```sh
  # Gitee配置
  链接名: Gitee
  GItee域名URL: https://gitee.com
  证书令牌: Gitee API 令牌 (git私人令牌)	# 选择这个
  ```

- 节点管理

  ```sh
  # 节点管理 > configure clouds
  名称: kubernetes
  kubernetes cloud details:
  	kubernetes地址: https://kubernetes.default	# kubernetes集群api地址 通过服务发现的方式以svc名称访问资源
  	kubernetes服务证书: 
  	禁用HTTPS证书检查
  	kubernetes命名空间: kube-devops	# agent容器将来运行哪个命名空间中
  	凭据: k8s连接 	# 选择~/.kube/config 其中的 certificate-authority-data
  	jenkins地址: http://jenkins-service.kube-devops:8080	# jenkins服务地址
  	Jenkins通道: http://jenkins-service.kube-devops:50000 # 用户与agent建立连接
  	容器数量: 10 	# 最大允许启动多少个agent容器
  ```

- Managed files

  ```sh
  # 存储kubeconfig
  # 在k8s集群的devops中,我妈经常会将构建以及部署过程放在临时pod中执行,所谓的slave pod
  # 因此在部署过程中需要将目标集群的kubeconfig传递到slave pod中,
  # 这样可以直接在pod中执行kubectl apply -f deploy.yaml --kubeconfig=config
  # managed files > add a new config > custom file > 
  # 在服务器上使用cat ~/.kube/config 复制完整内容 填入
  ```

##### 构建Jenkins任务

```shell
# Gitee webhook 触发构建，需要在 Gitee webhook 中填写 URL: http://192.168.28.120:32517/gitee-project/test  此为jenkins中任务地址 需要webhook可以访问远程的话
# Gitee WebHook 需要下载
# 流水线定义 Pipline script from SCM
# SCM: SCM
# Repository URL : git clone地址
# Credentials: gitee 用户名密码
# 分支选择
# 脚本路径 根目录下的Jenkinsfile


${GIT_BRANCH.replaceFirst(/^.*\//, '')}
BUILD_PROJECT_NAME=pforms-${GIT_BRANCH##origin/}
${GIT_BRANCH,fullName=false}-${BUILD_NUMBER}
```





```sh
# 

# gitee 配置
# 	连接名: gitee
# 	Gitee 域名 URL: https://gitee.com

```











```yaml
# 初始化密码
kubectl logs -f pod/jenkins-65c7744f5b-m2xhb -n kube-devops
# 
2b677be11d1d4f60a2b8b8efbb3edfb8



docker run  --network host -d -v /opt/k8s/devops/jenkins/manifests/frpc-tower-jenkins.ini:/etc/frp/frpc.ini --name frpc-jenkins snowdreamtech/frpc



[common]
server_addr = 101.33.197.5
server_port = 9978
tcp_mux = true
protocol = tcp
user = 36f57432284c9899fc3f35ee8ef95410
token = P7UiktkKscO7760Y
starry_token = 36f57432284c9899fc3f35ee8ef95410
dns_server = 114.114.114.114


[xLF02dir]
# 备注：jenkins-webhook
privilege_mode = true
type = tcp
local_ip = 127.0.0.1
local_port = 32517
remote_port = 32517
use_encryption = true
use_compression = true

# 全局配置
git config --global user.name "tower"
git config --global user.email "1446137304@qq.com"

# 初始化
mkdir k8s-cicd-demo
cd k8s-cicd-demo
git init -b "main"
touch README.md
git add README.md
git commit -m "first commit"
git remote add origin https://gitee.com/starsea777/k8s-cicd-demo.git
git push -u origin "main"
# 已有仓库
cd existing_git_repo
git remote add origin https://gitee.com/starsea777/k8s-cicd-demo.git
git push -u origin "main"
```

### 微服务Devops实战

#### 项目环境

##### redis

###### 删除无法一直无法删除的命名空间

```shell
# 取消删除pvc
kubectl patch pvc <pvc-name> -p '{"metadata":{"finalizers":null}}' --type=merge



# 将信息拿到   
kubectl geta ns redis -o json > redis-namespace.json

# 编辑redis-namespace.json  找到 spec 将 finalizers 下的 kubernetes 删除。
 
# 执行
kubectl replace --raw "/api/v1/namespaces/redis/finalize" -f redis-namespace.json



helm install redis ./redis/ -n redis



kubectl get  ns rocketmq  -o json > rocketmq-namespace.json
# 编辑rocketmq-namespace.json  找到 spec 将 finalizers 下的 kubernetes 删除。

kubectl replace --raw "/api/v1/namespaces/rocketmq/finalize" -f rocketmq-namespace.json
```

##### rocketmq

```shell
# 删除
helm uninstall rocketmq -n rocketmq

kubectl apply -f namespace.yaml
helm -n rocketmq install rocketmq -f examples/dev.yaml charts/rocketmq/

# 添加sc配置
storageClassName: managed-nfs-storage
```







```
kubectl describe pod/redis-replicas-0 -n redis

kubectl get all -n redis
kubectl describe pod/redis-replicas-1 -n redis


helm -n rocketmq install rocketmq -f ./examples/dev.yaml ./charts/rocketmq
kubectl get all -n rocketmq


kubectl get svc -n seate-server




http://redis-master.redis:6379
http://rocketmq-nameserver.rocketmq:9876
http://seata-headless.seate-server:8091
http://mysql-write.mysql:3306
http://nacos-headless.nacos:8848

```

##### mysql

```shell
mysql -u root -h 127.0.0.1
```

#### 服务

`
