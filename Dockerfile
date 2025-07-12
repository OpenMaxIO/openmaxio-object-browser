FROM docker.io/alpine:3.22

COPY console /bin/console

expose 9090

CMD [ "/bin/console", "server" ]