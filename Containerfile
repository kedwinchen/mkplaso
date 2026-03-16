FROM python:3

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  build-essential \
  redis \
  && \
  apt-get clean && \
  rm -rf /var/cache/apt /var/lib/apt/lists/*

RUN curl -L -o uv.tgz https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-unknown-linux-gnu.tar.gz && \
  tar xzvf uv.tgz && \
  mv uv-x86_64-unknown-linux-gnu/* /usr/local/bin && \
  rm -rf uv-x86_64-unknown-linux-gnu uv.tgz

RUN useradd \
  --create-home \
  --user-group \
  --shell /usr/sbin/nologin \
  worker && \
  mkdir -vp /plaso_input /plaso_output /plaso_tmp && \
  chown worker:worker /plaso_input /plaso_output /plaso_tmp

VOLUME [ "/plaso_input", "/plaso_output", "/plaso_tmp" ]

COPY --chmod=555 \
  mkplaso.bash /

USER worker

ENV PATH="/home/worker/.local/bin:$PATH"

RUN uv --no-cache tool install plaso

ENTRYPOINT ["/bin/bash", "-lx", "/mkplaso.bash"]
