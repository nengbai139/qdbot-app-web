import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../util/media_url.dart';

final _registeredThumbs = <String>{};

/// ponytail: 0.08s 跳过部分编码黑场；升级路径见 video_poster_web
const _thumbSeekSec = 0.08;

void _setupVideoThumb(web.HTMLVideoElement video, web.HTMLImageElement img) {
  void seekNext() {
    if (video.videoWidth == 0) return;
    video.pause();
    video.currentTime = _thumbSeekSec;
  }

  void paintFrame() {
    if (video.videoWidth == 0 || video.videoHeight == 0) return;
    const maxW = 400.0;
    final scale = video.videoWidth > maxW ? maxW / video.videoWidth : 1.0;
    final cw = (video.videoWidth * scale).round().clamp(1, 640);
    final ch = (video.videoHeight * scale).round().clamp(1, 360);
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = cw
      ..height = ch;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return;
    ctx.drawImage(video, 0, 0, cw.toDouble(), ch.toDouble());
    img.src = canvas.toDataURL('image/jpeg', 0.85.toJS);
    video.style.display = 'none';
    img.style.display = 'block';
  }

  video.addEventListener('loadeddata', ((web.Event _) => seekNext()).toJS);
  video.addEventListener('loadedmetadata', ((web.Event _) {
    if (img.style.display != 'block' && video.readyState >= 1) seekNext();
  }).toJS);
  video.addEventListener(
    'seeked',
    ((web.Event _) {
      video.pause();
      paintFrame();
    }).toJS,
  );
}

Widget buildVideoBubbleThumb(String url, {double width = 200, double height = 120}) {
  final src = publicMediaUrl(url);
  if (src.isEmpty) {
    return SizedBox(width: width, height: height);
  }
  final viewType = 'qdbot-vthumb-${src.hashCode}';
  if (!_registeredThumbs.contains(viewType)) {
    _registeredThumbs.add(viewType);
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final wrap = web.document.createElement('div') as web.HTMLDivElement
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden';
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..src = src
        ..muted = true
        ..playsInline = true
        ..preload = 'auto'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';
      final img = web.document.createElement('img') as web.HTMLImageElement
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.display = 'none';
      wrap.appendChild(video);
      wrap.appendChild(img);
      _setupVideoThumb(video, img);
      return wrap;
    });
  }
  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(viewType: viewType),
  );
}
