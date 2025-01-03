import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

const String _METHOD_CHANNEL_NAME = 'fit.system.screenshot.method';
const String _EVENT_CHANNEL_NAME = 'fit.system.screenshot.event';

typedef void OnScreenShotScroll(double offset);
typedef void Dispose();

final double radio = window.devicePixelRatio;

class _FitSystemScreenshot {
  MethodChannel? _methodChannel;
  StreamSubscription? _subscription;
  OnScreenShotScroll? onScreenShotScroll;
  bool isScreenShot = false;

  ///应用启动时调用，初始化截屏环境
  void init() {
    if (!Platform.isAndroid) return;
    _methodChannel = MethodChannel(_METHOD_CHANNEL_NAME);
    EventChannel _eventChannel = EventChannel(_EVENT_CHANNEL_NAME);
    _subscription = _eventChannel.receiveBroadcastStream().listen((args) {
      double? top = args['top'];
      if (top != null) {
        isScreenShot = true;
        onScreenShotScroll?.call(top / radio);
        isScreenShot = false;
      } else {
        // Handle null value scenario
        print('Warning: Received null for "top" from event stream');
      }
    }, onError: (error) {
      // Handle stream errors
      print('Error in event stream: $error');
    });
  }

  ///应用退出时调用，释放截屏资源
  void release() {
    if (!Platform.isAndroid) return;
    _subscription?.cancel();
  }

  ///当首屏页面数据加载完成后调用
  Dispose attachToPage<S extends State<StatefulWidget>>(
    GlobalKey<S> scrollAreaKey,
    ScrollController scrollController,
    OnScreenShotScroll onScreenShotScroll,
  ) {
    if (!Platform.isAndroid) return () {};
    bool isNestedScrollView = S.toString() == 'NestedScrollViewState';
    double currentScrollLength = 0;
    final refreshScrollLength = () {
      double newLength = 0;
      if (isNestedScrollView) {
        NestedScrollViewState? nestedState =
            scrollAreaKey.currentState as NestedScrollViewState?;
        if (nestedState != null) {
          ScrollPosition innerPos = nestedState.innerController.position;
          newLength += (innerPos.viewportDimension + innerPos.maxScrollExtent);
          ScrollPosition outPos = nestedState.outerController.position;
          newLength += outPos.maxScrollExtent;
        }
      } else {
        ScrollPosition position = scrollController.position;
        newLength = position.viewportDimension + position.maxScrollExtent;
      }
      if (currentScrollLength != newLength) {
        currentScrollLength = newLength;
        updateScrollLength(newLength);
      }
    };
    final onScrollListener = () {
      refreshScrollLength();
      if (!isScreenShot) updateScrollPosition(scrollController.offset);
    };
    SchedulerBinding.instance?.addPostFrameCallback((timeStamp) {
      this.onScreenShotScroll = onScreenShotScroll;
      updateScrollAreaWithKey(scrollAreaKey);
      refreshScrollLength();
      updateScrollPosition(scrollController.offset);
      scrollController.position.addListener(onScrollListener);
    });
    return () {
      this.onScreenShotScroll = null;
      if (scrollController.hasClients) {
        scrollController.position.removeListener(onScrollListener);
      }
    };
  }

  void updateScrollAreaWithKey(GlobalKey scrollAreaKey) {
    if (!Platform.isAndroid) return;
    BuildContext? context = scrollAreaKey.currentContext;
    if (context != null) {
      RenderObject? renderBox = (context as Element).renderObject;
      if (renderBox is RenderBox) {
        Size size = renderBox.size;
        Offset offset = renderBox.localToGlobal(Offset.zero);
        updateScrollArea(offset & size);
      }
    }
  }

  void updateScrollArea(Rect scrollArea) {
    if (!Platform.isAndroid) return;
    int top = (scrollArea.top * radio).toInt();
    int left = (scrollArea.left * radio).toInt();
    int width = (scrollArea.width * radio).toInt();
    int height = (scrollArea.height * radio).toInt();
    _methodChannel?.invokeMethod('updateScrollArea', {
      'top': top,
      'left': left,
      'width': width,
      'height': height,
    });
  }

  void updateScrollLength(double maxScrollExtent) {
    if (!Platform.isAndroid) return;
    _methodChannel?.invokeMethod(
      'updateScrollLength',
      {'length': maxScrollExtent * radio},
    );
  }

  void updateScrollPosition(double position) {
    if (!Platform.isAndroid) return;
    _methodChannel?.invokeMethod(
      'updateScrollPosition',
      {'position': position * radio},
    );
  }
}

_FitSystemScreenshot fitSystemScreenshot = _FitSystemScreenshot();
