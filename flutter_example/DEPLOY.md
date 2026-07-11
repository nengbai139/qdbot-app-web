# Web 部署到 jsDelivr CDN

## CDN 地址

```
https://cdn.jsdelivr.net/gh/nengbai139/qdbot-app-web-cdn@main/docs/
```

## 部署步骤

### 1. 构建 Flutter Web

```bash
cd /Users/baineng/Documents/devops/qdtech/qdbot_app/flutter_example

# 构建（禁用 PWA service worker）
flutter build web --release --base-href=/app_web/ --pwa-strategy=none

# 删除 service worker 文件
rm -f build/web/flutter_service_worker.js
```

### 2. 复制到 CDN 仓库

```bash
# 创建 CDN 仓库目录（如果还没有）
# mkdir -p /tmp/qdbot-app-web-cdn && cd /tmp/qdbot-app-web-cdn && git init && git remote add origin https://github.com/nengbai139/qdbot-app-web-cdn.git

# 复制构建产物
cp -r build/web/* /tmp/qdbot-app-web-cdn/docs/
```

### 3. 推送到 GitHub

```bash
cd /tmp/qdbot-app-web-cdn

# 添加文件并提交
git add docs/
git commit -m "Update web build $(date +%Y%m%d-%H%M%S)"

# 推送到 GitHub
git push
```

### 4. 验证 CDN

等待约 1 分钟让 jsDelivr 刷新缓存，然后访问：
- https://cdn.jsdelivr.net/gh/nengbai139/qdbot-app-web-cdn@main/docs/index.html

## 一键部署脚本

也可以直接运行：

```bash
cd /Users/baineng/Documents/devops/qdtech/qdbot_app/flutter_example

# 构建
flutter build web --release --base-href=/app_web/ --pwa-strategy=none
rm -f build/web/flutter_service_worker.js

# 复制并推送
rm -rf /tmp/qdbot-app-web-cdn/docs
mkdir -p /tmp/qdbot-app-web-cdn
cp -r build/web /tmp/qdbot-app-web-cdn/docs
cd /tmp/qdbot-app-web-cdn
git add docs/
git commit -m "Update $(date +%Y%m%d-%H%M%S)"
git push
```

## 直接访问主要文件

- [index.html](https://cdn.jsdelivr.net/gh/nengbai139/qdbot-app-web-cdn@main/docs/index.html)
- [main.dart.js](https://cdn.jsdelivr.net/gh/nengbai139/qdbot-app-web-cdn@main/docs/main.dart.js)
- [flutter_bootstrap.js](https://cdn.jsdelivr.net/gh/nengbai139/qdbot-app-web-cdn@main/docs/flutter_bootstrap.js)

## GitHub 仓库

- CDN 仓库：https://github.com/nengbai139/qdbot-app-web-cdn
- 源码仓库：https://github.com/nengbai139/qdbot-app-web
