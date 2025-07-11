FROM ubuntu:noble

RUN mkdir -p /build

WORKDIR /build

RUN apt update
RUN apt install git -y
RUN apt install curl -y
RUN apt install wget -y
RUN apt-get install build-essential -y


RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
RUN . /root/.nvm/nvm.sh ; nvm install 18
RUN . /root/.nvm/nvm.sh ; nvm use 18
RUN . /root/.nvm/nvm.sh ; corepack enable
RUN . /root/.nvm/nvm.sh ; corepack prepare yarn@4.4.0 --activate

RUN wget https://go.dev/dl/go1.23.5.linux-amd64.tar.gz
RUN tar -C /usr/local/ -xzf go1.23.5.linux-amd64.tar.gz
RUN export PATH=$PATH:/usr/local/go/bin




RUN git clone https://github.com/OpenMaxIO/openmaxio-object-browser 

WORKDIR /build/openmaxio-object-browser/web-app/

RUN git checkout v1.7.6

RUN . /root/.nvm/nvm.sh ; yarn install
RUN . /root/.nvm/nvm.sh ; yarn build

WORKDIR /build/openmaxio-object-browser
RUN export PATH=$PATH:/usr/local/go/bin ; make console



expose 9090


CMD [ "/build/openmaxio-object-browser/console", "server" ]
