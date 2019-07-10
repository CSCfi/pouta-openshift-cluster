FROM centos/python-27-centos7
LABEL maintainer="CSC Rahti Team <rahti-team@postit.csc.fi>"

# Output unbuffered text so that it shows on the Openshift dashboard and logs
ENV PYTHONUNBUFFERED 0
ENV LD_LIBRARY_PATH=/opt/rh/python27/root/usr/lib64

COPY * /opt/app-root/src/

RUN pip install -r requirements.txt

ENTRYPOINT python migrate.py
