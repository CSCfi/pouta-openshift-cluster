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
        tmux less git man bash-completion \
    && \
    yum clean all

RUN pip install --no-cache-dir -U setuptools
RUN pip install --no-cache-dir -r /root/requirements.txt

# Choose an arbitrary GID so that vault password can be made group readable when mounted as a volume
# in a reasonably safe way
RUN groupadd -g 29295 deployer
RUN useradd -u 29295 -g deployer -d /opt/deployment deployer

USER 29295

WORKDIR /opt/deployment

COPY init_env.bash init_env.bash
COPY run_playbook.bash run_playbook.bash
COPY bashrc .bashrc

CMD /usr/bin/bash