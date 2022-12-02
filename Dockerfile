# FROM python:3.6.13-slim-buster
FROM centos:7.8.2003 AS relay-deps

ENV PYTHON_VERSION 3.8.15

ENV PYTHON_PIP_VERSION 22.0.4

COPY ./python.tar.xz /

RUN set -x \
    && yum --nogpg install -y gcc make zlib-devel \
    && mkdir -p /usr/src/python \
    && tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
    && rm python.tar.xz* \
    && cd /usr/src/python \
    && ./configure --enable-shared \
    && make -j$(nproc) && make altinstall \
    && echo "/usr/local/lib/" > /etc/ld.so.conf.d/local.conf && ldconfig \
    && pip3.8 install -i https://mirrors.aliyun.com/pypi/simple/ --no-cache-dir --upgrade --ignore-installed pip==$PYTHON_PIP_VERSION \
    && find /usr/local \
        \( -type d -a -name test -o -name tests \) \
        -o \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
        -exec rm -rf '{}' + \
    && yum clean all \
    && rm -rf /usr/src/python

# make some useful symlinks that are expected to exist
RUN cd /usr/local/bin \
    && ln -s easy_install-3.8 easy_install3 \
    && ln -s idle3.8 idle3 \
    && ln -s pydoc3.8 pydoc3 \
    && ln -s python3.8 python \
    && ln -s python-config3.8 python-config3

ENV PATH="/usr/local/bin/python3/bin:${PATH}"

# Sane defaults for pip
ENV \
  PIP_NO_CACHE_DIR=off \
  PIP_DISABLE_PIP_VERSION_CHECK=1 \
  # Sentry config params
  SENTRY_CONF=/etc/sentry \
  # Disable some unused uWSGI features, saving dependencies
  # Thank to https://stackoverflow.com/a/25260588/90297
  UWSGI_PROFILE_OVERRIDE=ssl=false;xml=false;routing=false \
  # UWSGI dogstatsd plugin
  UWSGI_NEED_PLUGIN=/var/lib/uwsgi/dogstatsd \
  # grpcio>1.30.0 requires this, see requirements.txt for more detail.
  GRPC_POLL_STRATEGY=epoll1

WORKDIR /usr/src/snuba

COPY ./uwsgi-dogstatsd-bc56a1b5e7ee9e955b7a2e60213fc61323597a78.tar.gz /
COPY ./snuba-21.5.0.tar.gz .

# Copy and install dependencies first to leverage Docker layer caching.
RUN set -x \
  # && sed -i 's/snuba-sdk>=0.0.14,<1.0.0/snuba-sdk==0.0.14/g' /tmp/dist/requirements.txt \
  && buildDeps="" \
  # maxminddb
  && buildDeps="$buildDeps \
  glibc-devel \
  "\
  # xmlsec
  && buildDeps="$buildDeps \
  lz4-devel \
  pcre-devel \
  " \
  && yum makecache \
  && yum --nogpg install -y $buildDeps \
  && tar -xJC ./ --strip-components=1 -f snuba-21.5.0.tar.gz \
  && pip install -r ./requirements.txt \
  # 必须安装
  && mkdir /tmp/uwsgi-dogstatsd \
  && tar -xzf uwsgi-dogstatsd-bc56a1b5e7ee9e955b7a2e60213fc61323597a78.tar.gz -C /tmp/uwsgi-dogstatsd --strip-components=1 \
  && uwsgi --build-plugin /tmp/uwsgi-dogstatsd \
  && rm -rf /tmp/uwsgi-dogstatsd .uwsgi_plugins_builder \
  && mkdir -p /var/lib/uwsgi \
  && mv dogstatsd_plugin.so /var/lib/uwsgi/ \
  && yum clean all

RUN set -x \
  && tar -xJC ./ --strip-components=1 -f snuba-21.5.0.tar.xz \
  && chown -R xiaoju:xiaoju ./; \
  && pip install -e .; \
  && snuba --help;

ARG SNUBA_VERSION_SHA
ENV SNUBA_RELEASE=$SNUBA_VERSION_SHA \
  FLASK_DEBUG=0 \
  PYTHONUNBUFFERED=1 \
  PYTHONDONTWRITEBYTECODE=1 \
  UWSGI_ENABLE_METRICS=true \
  UWSGI_NEED_PLUGIN=/var/lib/uwsgi/dogstatsd \
  UWSGI_STATS_PUSH=dogstatsd:127.0.0.1:8126 \
  UWSGI_DOGSTATSD_EXTRA_TAGS=service:snuba