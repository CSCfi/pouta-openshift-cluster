FROM centos:7

MAINTAINER CSC Container Team <container-team@postit.csc.fi>

COPY requirements.txt /root/requirements.txt

RUN yum install -y \
        epel-release \
    && \
    yum install -y \
        openssh-clients \
        python-devel python2-pip \
        gcc openssl-devel \
        java-1.8.0-openjdk-headless httpd-tools \
        tmux less \
    && \
    yum clean all

RUN pip install --no-cache-dir -U setuptools
RUN pip install --no-cache-dir -r /root/requirements.txt

RUN useradd -u 1001 -d /opt/deployment deployer

USER 1001

WORKDIR /opt/deployment

CMD /usr/bin/bash
