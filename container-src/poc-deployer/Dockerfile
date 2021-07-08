FROM centos:8

LABEL maintainer="CSC Rahti Team <rahti-team@postit.csc.fi>"

RUN dnf install -y \
        epel-release \
    && \
    dnf install -y \
        openssh-clients \
        python3-pip \
        openssl \
        httpd-tools \
        glibc-langpack-en \
        jq \
        tmux less git man bash-completion \
        which \
        java-1.8.0-openjdk-devel \
    && \
    dnf clean all

COPY requirements.txt /root/requirements.txt

# Set default python version and install packages
RUN alternatives --set python /usr/bin/python3 \
    && pip3 install --no-cache-dir -U setuptools wheel \
    && pip3 install --no-cache-dir -r /root/requirements.txt

# Choose an arbitrary GID so that vault password can be made group readable when mounted as a volume
# in a reasonably safe way
RUN groupadd -g 29295 deployer \
    && useradd -u 29295 -g deployer -d /opt/deployment deployer

# set POC ansible.cfg as the default
ENV ANSIBLE_CONFIG=/opt/deployment/poc/playbooks/ansible.cfg

USER 29295

WORKDIR /opt/deployment

COPY init_env.bash init_env.bash
COPY run_playbook.bash run_playbook.bash
COPY run_backup.bash run_backup.bash
COPY cinder_csi_restart.bash cinder_csi_restart.bash
COPY bashrc .bashrc

ADD mitogen-0.2.9.tar.gz /opt/deployment

CMD /usr/bin/bash
