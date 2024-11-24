FROM nginx:latest
LABEL authors="tower"

COPY nginx.conf /etc/nginx/nginx.conf
COPY cert/ /etc/nginx/cert/
COPY public/ /usr/share/nginx/html/


ENV TZ=Asia/Shanghainginx
EXPOSE 80
EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]


