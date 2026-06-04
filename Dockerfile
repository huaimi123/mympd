FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    build-essential meson pkg-config git \
    libmpdclient-dev libffmpeg-dev libflac-dev libvorbis-dev \
    libopus-dev libsqlite3-dev libao-dev libpulse-dev libicu-dev \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /output
RUN git clone https://github.com/MusicPlayerDaemon/MPD.git /mpd-src && \
    cd /mpd-src && meson setup build --buildtype=release && ninja -C build && cp build/mpd /output/mpd
RUN git clone https://github.com/MusicPlayerDaemon/mpc.git /mpc-src && \
    cd /mpc-src && meson setup build --buildtype=release && ninja -C build && cp build/mpc /output/mpc
