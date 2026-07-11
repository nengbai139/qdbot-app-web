#!/usr/bin/env python3
# Flutter Web 上传到阿里云 OSS
import oss2
import os
import sys
import time

# OSS 配置
OSS_ENDPOINT = 'oss-cn-beijing.aliyuncs.com'
OSS_BUCKET = 'qdbot-web-bucket'
OSS_ACCESS_KEY_ID = os.environ.get('OSS_ACCESS_KEY_ID', '')
OSS_ACCESS_KEY_SECRET = os.environ.get('OSS_ACCESS_KEY_SECRET', '')
REMOTE_PATH = 'app_web'

# 检查密钥
if not OSS_ACCESS_KEY_ID or not OSS_ACCESS_KEY_SECRET:
    print("错误: 请设置环境变量 OSS_ACCESS_KEY_ID 和 OSS_ACCESS_KEY_SECRET")
    sys.exit(1)

def upload_directory(bucket, local_dir, remote_path):
    """上传目录到 OSS"""
    uploaded = 0
    failed = []

    for root, dirs, files in os.walk(local_dir):
        # 跳过隐藏文件
        dirs[:] = [d for d in dirs if not d.startswith('.')]

        for file in files:
            if file.startswith('.'):
                continue

            local_path = os.path.join(root, file)
            rel_path = os.path.relpath(local_path, local_dir)
            remote_key = f"{remote_path}/{rel_path}".replace('\\', '/')

            # 跳过 service worker
            if 'service_worker' in file.lower():
                print(f"跳过: {local_path}")
                continue

            try:
                bucket.put_object_from_file(remote_key, local_path)
                uploaded += 1
                if uploaded % 10 == 0:
                    print(f"已上传 {uploaded} 个文件...")
            except Exception as e:
                failed.append((local_path, str(e)))
                print(f"失败: {local_path} - {e}")

    return uploaded, failed

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    build_dir = os.path.join(project_dir, 'build', 'web')

    if not os.path.exists(build_dir):
        print(f"错误: 找不到构建目录 {build_dir}")
        print("请先运行: flutter build web --release --base-href=/app_web/")
        sys.exit(1)

    print(f"Flutter Web 目录: {build_dir}")
    print(f"OSS Bucket: {OSS_BUCKET}")
    print(f"上传路径: {REMOTE_PATH}/")
    print()

    # 创建 Bucket
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    bucket = oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET)

    # 检查 bucket 访问权限
    try:
        bucket.get_bucket_info()
        print("Bucket 连接成功!")
    except oss2.exceptions.ServerError as e:
        print(f"Bucket 访问失败: {e}")
        print("请检查 AccessKey 权限和 Bucket ACL 设置")
        sys.exit(1)

    print(f"\n开始上传...")
    start = time.time()

    uploaded, failed = upload_directory(bucket, build_dir, REMOTE_PATH)

    elapsed = time.time() - start

    print(f"\n上传完成!")
    print(f"成功: {uploaded} 个文件")
    print(f"失败: {len(failed)} 个文件")
    print(f"耗时: {elapsed:.1f} 秒")

    if failed:
        print("\n失败的文件:")
        for path, err in failed[:10]:
            print(f"  - {path}: {err}")

    cdn_url = f"https://{OSS_BUCKET}.{OSS_ENDPOINT}/{REMOTE_PATH}/"
    print(f"\n访问地址: {cdn_url}")

if __name__ == '__main__':
    main()
