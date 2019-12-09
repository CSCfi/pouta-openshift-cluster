FROM centos:7

LABEL maintainer="CSC Rahti Team <rahti-team@postit.csc.fi>"

RUN yum install -y \
        epel-release \
    && \
    yum install -y \
        openssh-clients \
        python-devel python2-pip \
        gcc openssl-devel openssl \
        java-1.8.0-openjdk-headless httpd-tools \
        jq \
        tmux less git man bash-completion \
    && \
    yum clean all

COPY requirements.txt /root/requirements.txt

RUN pip install --no-cache-dir -U setuptools wheel
RUN pip install --no-cache-dir -r /root/requirements.txt

# Choose an arbitrary GID so that vault password can be made group readable when mounted as a volume
# in a reasonably safe way
RUN groupadd -g 29295 deployer
RUN useradd -u 29295 -g deployer -d /opt/deployment deployer

# set POC ansible.cfg as the default
ENV ANSIBLE_CONFIG=/opt/deployment/poc/playbooks/ansible.cfg

USER 29295

WORKDIR /opt/deployment

COPY init_env.bash init_env.bash
COPY run_playbook.bash run_playbook.bash
COPY run_backup.bash run_backup.bash
COPY bashrc .bashrc

ADD mitogen-0.2.7.tar.gz /opt/deployment

CMD /usr/bin/bash
