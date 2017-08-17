FROM nginx:alpine

MAINTAINER CSC Container Team <container-team@postit.csc.fi>

RUN chown 123456789.root /var/cache/nginx /var/run
RUN chmod -R g+w /var/cache/nginx /var/run

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8888

USER 123456789
