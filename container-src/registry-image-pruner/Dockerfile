FROM centos:7
MAINTAINER CSC Rahti Team <rahti-team@postit.csc.fi>
ENV OC_VERSION "v3.9.0"
ENV OC_RELEASE "openshift-origin-client-tools-v3.9.0-191fece-linux-64bit.tar.gz"
ENV KUBECONFIG "/tmp/.kube/config"

# install the oc client tools
ADD https://github.com/openshift/origin/releases/download/$OC_VERSION/$OC_RELEASE /opt/oc/release.tar.gz
RUN tar --strip-components=1 -xzvf  /opt/oc/release.tar.gz -C /opt/oc/ && \
    mv /opt/oc/oc /usr/bin/ && \
    rm -rf /opt/oc

ADD prune-images.sh /usr/bin
