import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quick_video_encoder_fork/flutter_quick_video_encoder.dart';
import 'package:widget_record_video/src/recording_controller.dart';
import 'package:widget_record_video/src/utils.dart';

class RecordingWidget extends StatefulWidget {
  const RecordingWidget({
    super.key,
    required this.child,
    required this.controller,
    this.limitTime = 120,
    required this.onComplete,
    this.outputPath,
  });

  /// This is the widget you want to record the screen
  final Widget child;

  /// [RecordingController] Used to start, pause, or stop screen recording
  final RecordingController controller;

  /// [limitTime] is the video recording time limit, when the limit is reached, the process automatically stops.
  /// Its default value is 120 seconds. If you do not have a limit, please set the value -1
  final int limitTime;

  /// [onComplete] is the next action after creating a video, it returns the video path
  final Function(String) onComplete;

  /// [outputPath] output address of the video, make sure you have write permission to this location otherwise leave it null, it will automatically be saved to app cache
  final String? outputPath;

  @override
  State<RecordingWidget> createState() => _RecordingWidgetState();
}

class _RecordingWidgetState extends State<RecordingWidget> {
  static const int fps = 30;

  @override
  void initState() {
    super.initState();
    widget.controller.start = startRecording;
    widget.controller.stop = stopRecording;
    widget.controller.pauseRecord = pauseRecording;
    widget.controller.continueRecord = continueRecording;
  }

  Directory? tempDir;

  Future<void> getImageSize() async {
    RenderRepaintBoundary boundary =
        recordKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage(pixelRatio: 1);
    width = image.width;
    height = image.height;
  }

  GlobalKey recordKey = GlobalKey();
  int frameIndex = 0;
  bool isRecording = false;
  Timer? timer;
  int width = 0;
  int height = 0;

  bool isPauseRecord = false;

  BuildContext? _context;

  int elapsedTime = 0;

  void startRecording() {
    setState(() {
      isRecording = true;
      elapsedTime = 0;
    });
    startExportVideo();
    timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (elapsedTime >= widget.limitTime) {
        stopRecording();
      } else if (!isPauseRecord) {
        setState(() {
          elapsedTime++;
        });
      }
    });
  }

  Future stopRecording() async {
    timer?.cancel();
    setState(() {
      isRecording = false;
    });
  }

  void pauseRecording() {
    isPauseRecord = true;
  }

  void continueRecording() {
    isPauseRecord = false;
  }

  Future<void> startExportVideo() async {
    Directory? appDir = await getApplicationCacheDirectory();

    try {
      int startTime = DateTime.now().millisecondsSinceEpoch;
      await getImageSize();

      await FlutterQuickVideoEncoder.setup(
        width: (width ~/ 2) * 2,
        height: (height ~/ 2) * 2,
        fps: fps,
        videoBitrate: 1000000,
        profileLevel: ProfileLevel.any,
        audioBitrate: 0,
        audioChannels: 0,
        sampleRate: 0,
        filepath: '${appDir.path}/exportVideoOnly.mp4',
      );

      Completer<void> readyForMore = Completer<void>();
      readyForMore.complete();

      while (isRecording) {
        Uint8List? videoFrame;
        Uint8List? audioFrame;

        if (!isPauseRecord) {
          videoFrame = await captureWidgetAsRGBA();

          await readyForMore.future;
          readyForMore = Completer<void>();

          try {
            _appendFrames(videoFrame, audioFrame)
                .then((value) => readyForMore.complete())
                .catchError((e) => readyForMore.completeError(e));
          } catch (e) {
            debugPrint(e.toString());
          }
        } else {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      await readyForMore.future;

      await FlutterQuickVideoEncoder.finish();
      int endTime = DateTime.now().millisecondsSinceEpoch;
      int videoTime = ((endTime - startTime) / 1000).round() - 1;
      debugPrint("video time: $videoTime");

      var resultPath = await Ultis.adjustVideoSpeed(
        FlutterQuickVideoEncoder.filepath,
        videoTime,
        widget.outputPath,
      );
      widget.onComplete(resultPath);

      FlutterQuickVideoEncoder.dispose();
    } catch (e) {
      ('Error: $e');
    }
  }

  Future<Uint8List?> captureWidgetAsRGBA() async {
    try {
      RenderRepaintBoundary boundary =
          recordKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 1);
      width = image.width;
      height = image.height;

      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint(
        e.toString(),
      );
      return null;
    }
  }

  Future<void> _appendFrames(
      Uint8List? videoFrame, Uint8List? audioFrame) async {
    if (videoFrame != null) {
      await FlutterQuickVideoEncoder.appendVideoFrame(videoFrame);
    } else {
      debugPrint("Error append $videoFrame");
    }
  }

  void showSnackBar(String message) {
    debugPrint(message);
    final snackBar = SnackBar(content: Text(message));
    if (_context != null && _context!.mounted) {
      ScaffoldMessenger.of(_context!).showSnackBar(snackBar);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _context = context;
    return Scaffold(
      body: RepaintBoundary(
        key: recordKey,
        child: widget.child,
      ),
    );
  }
}
