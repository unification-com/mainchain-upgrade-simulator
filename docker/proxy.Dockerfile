FROM nginx:stable-alpine
COPY generated/assets/nginx.conf /etc/nginx/conf.d
CMD ["/bin/sh", "-c", "exec nginx -g 'daemon off;';"]
WORKDIR /usr/share/nginx/html
