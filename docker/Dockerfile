FROM ubuntu:18.04
MAINTAINER Dereck Zenda<dereck.zenda@gmail.com>

ENV MODULE_NUMBER=1

#install python

RUN apt-get update \
  && apt-get install -y python3.6 python3-pip python3-dev \
  && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 2 \
  && cd /usr/local/bin \
  && ln -s /usr/bin/python3 python \
  && pip3 install --upgrade pip

#add Module
RUN mkdir /app
ADD . /app

#remove unnecessary files
RUN rm -f /app/Dockerfile

#install required packages
RUN pip3.6 install -r /app/requirements.txt

CMD ["python /app/main.py"]
