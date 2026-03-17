FROM nginx:1.29.5-alpine-slim

COPY src/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80


