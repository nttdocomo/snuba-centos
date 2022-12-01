# FROM python:3.6.13-slim-buster
FROM centos:7.8.2003 AS relay-deps

ENV PYTHON_VERSION 3.8.15

ENV PYTHON_PIP_VERSION 22.0.4

COPY ./python.tar.xz /

RUN set -x \
    && yum --nogpg install -y gcc make \
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