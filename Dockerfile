FROM ruby:2.6.5-slim

ENV LANG C.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV BUNDLE_PATH /bundle
ENV SBI_SECURITY_USER_ID=""
ENV SBI_SECURITY_PASSWORD=""

# set locale and timezone
RUN apt-get update -qq && \
  apt-get -y upgrade && \
  apt-get -y install locales && \
  echo en_US.UTF-8 UTF-8 > /etc/locale.gen && locale-gen && dpkg-reconfigure locales && \
  echo "Asia/Tokyo" > /etc/timezone && dpkg-reconfigure -f noninteractive tzdata

ENV TZ Asia/Tokyo


RUN apt-get -y --no-install-recommends install \
  build-essential \
  curl \
  wget \
  libappindicator1 \
  fonts-liberation \
  libappindicator3-1 \
  libasound2 \
  libatk-bridge2.0-0 \
  libatspi2.0-0 \
  libgtk-3-0 \
  libnspr4 \
  libnss3 \
  libx11-xcb1 \
  libxss1 \
  libxtst6 \
  lsb-release \
  xdg-utils \
  apt-transport-https \
  git

RUN curl -O https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
RUN dpkg -i google-chrome-stable_current_amd64.deb

RUN apt-get clean && \
    apt-get autoclean && \
    apt-get -y autoremove

COPY . /root/app

WORKDIR /root/app

RUN bundle install -j4

RUN bundle exec rake webdrivers:chromedriver:update[2.35]

ENV PATH $PATH:/root/.webdrivers/
