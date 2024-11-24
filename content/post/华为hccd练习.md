---
# Documentation: https://docs.hugoblox.com/managing-content/

title: "华为hccd练习"
subtitle: "华为hccd练习笔记"
summary: "华为云原生平台学习笔记"
authors: []
tags: []
categories: ["笔记", "k8s"]
date: 2023-08-24T16:03:10+08:00
lastmod: 2023-08-30T16:03:10+08:00
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



```sh
systemctl stop firewalld && systemctl disable firewalld
setenforce 0

# 配置docker仓库
yum install -y yum-utils
yum-config-manager --add-repo https://sandbox-expriment-files.obs.cn-north-1.myhuaweicloud.com:443/study-container/docker-ce.repo

# 安装docker容器服务 并开启
yum install -y docker-ce docker-ce-cli containerd.io
systemctl start docker
systemctl enable docker

vim /etc/docker/daemon.json
{
    "registry-mirrors":["https://0c9438a30a00f22f0fdcc01196c2bce0.mirror.swr.myhuaweicloud.com"]
}

# 重启docker
systemctl restart docker
systemctl status docker

# 运行容器
docker run -d -p 80:80 httpd

# 查看容器信息
docker container ls
docker image ls 

# 启动容器
docker stop 容器ID
docker start 容器ID

# 删除容器
docker stop 容器ID
docker rm 容器ID

# 取centos7镜像
docker pull centos:centos7
# 运行容器
docker run -t -d centos:centos7

# 进入容器
docker exec -it 容器ID bash

```



```shell
# 容器内执行
yum install -y vim

# 若出现Failed to download metadata for repo 'AppStream': Cannot prepare internal mirrorlist: No URLs in mirrorlist报错。请在容器内输入以下命令更换yum源，再重新安装vim。（若安装成功则跳过此步骤使用vim --version命令进行验证）
cd /etc/yum.repos.d/
#sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
# sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*


yum update -y 

yum install -y vim

vim --version

exit
```



```shell

docker commit 容器ID centos-vim

docker image ls

 docker rm -f c1af196ca24b
```



```shell
vim dockerfile

# dockerfile
FROM centos:centos7
MAINTAINER Iris@huawei.com
ENV HOSTNAME webserver
EXPOSE 80
RUN yum install -y httpd vi && yum clean all
VOLUME ["/var/www/html"]
CMD ["/usr/sbin/httpd","-D","FOREGROUND"]

docker build -t httpd-centos -f dockerfile /root

docker run -d -p 80:80 httpd-centos
```



```shell
# 搭建私有仓库
docker run -d -p 5000:5000 registry
# 利用docker tag命令修改镜像名称
docker tag httpd-centos localhost:5000/http:V1
# 将本地镜像上传至私有镜像仓库
docker push localhost:5000/http:V1
# 查看私有镜像registry中镜像信息
curl -X GET http://localhost:5000/v2/_catalog
curl -X GET http://localhost:5000/v2/http/tags/list

# 删除本地容器镜像
docker rmi httpd-centos
docker rmi localhost:5000/http:V1
```



```shell
# 容器生命周期

# 运行一个容器
docker run -d centos
docker container ls
```





```shell
# 运行一个压力测试容器，实践容器内存分配限额。
docker run -it -m 200M progrium/stress --vm 1 --vm-bytes 150M
docker run -it -m 200M progrium/stress --vm 1 --vm-bytes 250M

# stress是一个集成Linux压测实测工具的容器，可以实现对cpu、memory、IO等资源的压力测试。②运行一个压力测试容器，实践容器内存和swap分配限额
docker run -it -m 300M --memory-swap=400M progrium/stress --vm 2 --vm-bytes 100M

# 运行一个压力测试容器，实践容器CPU使用限额。
docker run -it --cpus=0.6 progrium/stress --vm 1


```



```shell
LANG=en_us.UTF-8 ssh root@123.249.35.56


wget https://dl.k8s.io/v1.23.14/kubernetes-client-linux-amd64.tar.gz
```



```dockerfile
FROM 100.125.0.78:20202/op_svc_cse/tomcat-x86_64:8.5.51-jdk8-openjdk-slim-int-1.0

WORKDIR /home/apps/

COPY target/*.jar app.jar

RUN sh -c 'touch app.jar'

ENTRYPOINT [ "sh", "-c", "java -Djava.security.egd=file:/dev/./urandom -jar -Xmx256m app.jar" ]
```











