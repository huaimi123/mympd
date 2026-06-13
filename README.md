# MPD 二进制构建脚本

这个项目包含了为不同平台构建 MPD (Music Player Daemon) 和 MPC (Music Player Client) 二进制文件的脚本。

## 支持的平台

| 平台 | 架构 | 运行时 | 说明 |
|------|------|--------|------|
| linux-arm64-glibc | ARM64 | glibc | 适用于大多数基于 glibc 的 ARM64 Linux 系统 |
| linux-arm64-musl | ARM64 | musl | 适用于 Alpine Linux 或其他基于 musl 的 ARM64 系统 |
| linux-armv7-glibc | ARMv7 | glibc | 适用于基于 glibc 的 ARMv7 Linux 系统（树莓派等） |
| linux-x86_64-glibc | x86_64 | glibc | 适用于大多数基于 glibc 的 x86_64 Linux 系统 |
| linux-x86_64-musl | x86_64 | musl | 适用于 Alpine Linux 或其他基于 musl 的 x86_64 系统 |

## 目录结构

```
mpd二进制构建/
├── build-linux-arm64-glibc.sh      # ARM64 glibc 构建脚本
├── build-linux-arm64-musl.sh       # ARM64 musl 构建脚本
├── build-linux-armv7-glibc.sh      # ARMv7 glibc 构建脚本
├── build-linux-x86_64-glibc.sh     # x86_64 glibc 构建脚本
├── build-linux-x86_64-musl.sh      # x86_64 musl 构建脚本
├── .github/
│   └── workflows/
│       └── build.yml               # GitHub Actions 工作流
└── README.md                       # 本文件
```

## 本地构建

### 前提条件

1. **系统要求**: Ubuntu/Debian Linux
2. **必要工具**:
   ```bash
   sudo apt-get update
   sudo apt-get install -y \
     debootstrap qemu-user-static \
     curl git meson ninja-build \
     patchelf pkg-config
   ```

3. **Chroot 环境准备**:

   对于 ARM 平台，需要先创建对应的 chroot 环境：

   ```bash
   # ARM64 glibc
   sudo mkdir -p /workspace/chroots/arm64-glibc
   sudo debootstrap --arch=arm64 bookworm /workspace/chroots/arm64-glibc http://deb.debian.org/debian
   sudo cp /usr/bin/qemu-aarch64-static /workspace/chroots/arm64-glibc/usr/bin/
   
   # ARM64 musl
   sudo mkdir -p /workspace/chroots/arm64-musl
   # 下载 Alpine rootfs
   curl -L -o /tmp/alpine-rootfs.tar.gz "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/alpine-minirootfs-3.23.0-aarch64.tar.gz"
   sudo tar -xzf /tmp/alpine-rootfs.tar.gz -C /workspace/chroots/arm64-musl
   sudo cp /usr/bin/qemu-aarch64-static /workspace/chroots/arm64-musl/usr/bin/
   
   # ARMv7 glibc
   sudo mkdir -p /workspace/chroots/armv7-glibc
   sudo debootstrap --arch=armhf bookworm /workspace/chroots/armv7-glibc http://deb.debian.org/debian
   sudo cp /usr/bin/qemu-arm-static /workspace/chroots/armv7-glibc/usr/bin/
   
   # x86_64 musl (使用 Alpine 容器)
   docker run --name alpine-build alpine:latest
   ```

### 构建步骤

1. **赋予执行权限**:
   ```bash
   chmod +x build-linux-*.sh
   ```

2. **选择要构建的平台**:
   ```bash
   # 构建 x86_64 glibc (不需要 chroot)
   ./build-linux-x86_64-glibc.sh
   
   # 构建 ARM64 glibc (需要 chroot)
   sudo ./build-linux-arm64-glibc.sh
   
   # 构建 ARM64 musl (需要 chroot)
   sudo ./build-linux-arm64-musl.sh
   
   # 构建 ARMv7 glibc (需要 chroot)
   sudo ./build-linux-armv7-glibc.sh
   
   # 构建 x86_64 musl (需要容器)
   docker run -v $(pwd):/workspace -w /workspace alpine:latest ./build-linux-x86_64-musl.sh
   ```

3. **查找构建产物**:
   ```bash
   # 构建产物位置
   ls -lh workspace/linux-*/archive/*.tgz
   ```

## GitHub Actions 自动构建

### 设置

1. **将代码推送到 GitHub**:
   ```bash
   git init
   git add .
   git commit -m "Add MPD build scripts"
   git branch -M main
   git remote add origin https://github.com/your-username/your-repo.git
   git push -u origin main
   ```

2. **启用 GitHub Actions**:
   - 访问仓库的 Actions 页面
   - 点击 "I understand my workflows, go ahead and enable them"

3. **手动触发构建**:
   - 访问 Actions 页面
   - 选择 "MPD Binary Build" 工作流
   - 点击 "Run workflow" 按钮

### 构建结果

- **产物**: 每个平台的压缩包会作为 GitHub Actions Artifacts 保存
- **Release**: 推送到 `main` 分支时会自动创建 GitHub Release

## 使用构建产物

1. **下载对应的压缩包**
2. **解压缩**:
   ```bash
   tar -xzf mpd-player-linux-*.tgz
   ```

3. **运行 MPD**:
   ```bash
   ./mpd    # 启动 MPD 服务
   ./mpc    # 运行 MPC 客户端
   ```

## 注意事项

### 依赖和运行时

- **glibc 版本**: 适用于大多数 Linux 发行版（Ubuntu, Debian, Fedora, CentOS 等）
- **musl 版本**: 专门为 Alpine Linux 或其他轻量级发行版设计
- **架构选择**: 确保选择与目标系统匹配的架构（`uname -m` 查看）

### 文件大小参考

| 平台 | 文件大小 | 文件数量 |
|------|----------|----------|
| linux-arm64-glibc | ~26MB | ~71个文件 |
| linux-arm64-musl | ~9.4MB | ~46个文件 |
| linux-armv7-glibc | ~11MB | ~68个文件 |
| linux-x86_64-glibc | ~25MB | ~70个文件 |
| linux-x86_64-musl | ~8MB | ~40个文件 |

### 故障排除

1. **Chroot 环境问题**:
   ```bash
   # 检查 QEMU 是否正常工作
   qemu-aarch64-static --version
   
   # 检查 chroot 文件系统挂载
   mount | grep chroot
   ```

2. **依赖库问题**:
   ```bash
   # 检查二进制文件依赖
   ldd mpd.real
   ```

3. **权限问题**:
   ```bash
   # 确保脚本有执行权限
   chmod +x build-linux-*.sh
   
   # 检查文件权限
   ls -la workspace/
   ```

## 贡献

欢迎提交问题和改进建议！

## 许可证

本项目遵循与 MPD 项目相同的许可证（GPL-2.0 或更高版本）。

## 相关链接

- [MPD 官方网站](https://www.musicpd.org/)
- [MPD GitHub 仓库](https://github.com/MusicPlayerDaemon/MPD)
- [MPC GitHub 仓库](https://github.com/MusicPlayerDaemon/mpc)