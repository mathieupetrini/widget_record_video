import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:record/record.dart';
import 'package:widget_record_video/src/recording_controller.dart';

class RecordingWidget extends StatefulWidget {
  const RecordingWidget({
    super.key,
    required this.child,
    required this.controller,
    this.limitTime = 120,
    required this.onComplete,
    this.outputPath,
    this.pixelRatio = 1,
    this.sampleRate = 48000,
    this.audioChannels = 1,
    this.audioBitrate = 64000,
  });

  /// This is the widget you want to record the screen
  final Widget child;

  /// [RecordingController] Used to start, pause, or stop screen recording
  final RecordingController controller;

  /// [limitTime] is the video recording time limit, when the limit is reached, the process automatically stops.
  /// Its default value is 120 seconds. If you do not have a limit, please set the value -1
  final int limitTime;

  /// [pixelRatio] The pixel ratio compared to the original widget. You should keep it at 1
  /// and only change it from 0.5 to 2 to ensure the best performance
  final double pixelRatio;

  final int sampleRate;
  final int audioChannels;
  final int audioBitrate;

  /// [onComplete] is the next action after creating a video, it returns the video path
  final Function(String) onComplete;

  /// [outputPath] output address of the video, make sure you have write permission to this location otherwise leave it null, it will automatically be saved to app cache
  final String? outputPath;

  @override
  State<RecordingWidget> createState() => _RecordingWidgetState();
}

class _RecordingWidgetState extends State<RecordingWidget> {
  static const int fps = 30;
  static const int audioChannels = 1;

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
    ui.Image image = await boundary.toImage(pixelRatio: widget.pixelRatio);
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

  List<int> convertBytesToInt16(Uint8List data) {
    var bytesPerSample = 2;
    var isLittleEndian = true;
    List<int> values = [];

    for (int i = 0; i < data.lengthInBytes; i += bytesPerSample) {
      int sample = 0;
      for (int j = 0; j < bytesPerSample; j++) {
        int byte =
        isLittleEndian ? data[i + j] : data[i + bytesPerSample - j - 1];
        sample |= byte << (j * 8);
      }
      // Process the PCM sample (interpret as signed 16-bit integer)
      values.add(sample.toSigned(16));
    }

    return values;
  }

  Uint8List convertPcmToWav(List<int> pcmData,
      {int sampleRate = 44100, int numChannels = 1, int bitsPerSample = 16}) {
    // Validate that pcmData values are in 16-bit range
    for (int sample in pcmData) {
      if (sample < -32768 || sample > 32767) {
        throw ArgumentError("PCM data value out of range for 16-bit audio");
      }
    }

    // Create a ByteData to write the WAV file
    var wavHeaderSize = 44; // Standard WAV header size
    var totalSize = wavHeaderSize + pcmData.length * 2;
    var byteData = ByteData(totalSize);

    // Write the RIFF header
    byteData.setUint8(0, 'R'.codeUnitAt(0));
    byteData.setUint8(1, 'I'.codeUnitAt(0));
    byteData.setUint8(2, 'F'.codeUnitAt(0));
    byteData.setUint8(3, 'F'.codeUnitAt(0));
    byteData.setUint32(4, totalSize - 8, Endian.little);
    byteData.setUint8(8, 'W'.codeUnitAt(0));
    byteData.setUint8(9, 'A'.codeUnitAt(0));
    byteData.setUint8(10, 'V'.codeUnitAt(0));
    byteData.setUint8(11, 'E'.codeUnitAt(0));

    // Write the fmt subchunk
    byteData.setUint8(12, 'f'.codeUnitAt(0));
    byteData.setUint8(13, 'm'.codeUnitAt(0));
    byteData.setUint8(14, 't'.codeUnitAt(0));
    byteData.setUint8(15, ' '.codeUnitAt(0));
    byteData.setUint32(16, 16, Endian.little); // Subchunk size
    byteData.setUint16(20, 1, Endian.little); // Audio format (1 = PCM)
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * numChannels * (bitsPerSample ~/ 8),
        Endian.little); // Byte rate
    byteData.setUint16(
        32, numChannels * (bitsPerSample ~/ 8), Endian.little); // Block align
    byteData.setUint16(34, bitsPerSample, Endian.little);

    // Write the data subchunk
    byteData.setUint8(36, 'd'.codeUnitAt(0));
    byteData.setUint8(37, 'a'.codeUnitAt(0));
    byteData.setUint8(38, 't'.codeUnitAt(0));
    byteData.setUint8(39, 'a'.codeUnitAt(0));
    byteData.setUint32(40, pcmData.length * 2, Endian.little);
    for (int i = 0; i < pcmData.length; i++) {
      byteData.setInt16(wavHeaderSize + i * 2, pcmData[i], Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  Future<void> startExportVideo() async {
    Directory? appDir = await getApplicationCacheDirectory();

    try {
      int startTime = DateTime.now().millisecondsSinceEpoch;
      await getImageSize();

      await FlutterQuickVideoEncoder.setup(
        width: width,
        height: height,
        fps: fps,
        videoBitrate: 1000000,
        profileLevel: ProfileLevel.any,
        audioBitrate: widget.audioBitrate,
        audioChannels: widget.audioChannels,
        sampleRate: widget.sampleRate,
        filepath: '${appDir.path}/exportVideoOnly.mp4',
      );

      Completer<void> readyForMore = Completer<void>();
      readyForMore.complete();
      Uint8List? audioFrame;
      Uint8List? audioFinal;

      final record = AudioRecorder();
      final stream = await record.startStream(RecordConfig(bitRate: widget.audioBitrate, encoder: AudioEncoder.pcm16bits, sampleRate: widget.sampleRate, numChannels: widget.audioChannels));
      stream.listen((event) {
        audioFrame = event;
      });

      const int bytesPerSample = 2;

      while (isRecording) {
        Uint8List? videoFrame;

        if (!isPauseRecord) {
          videoFrame = await captureWidgetAsRGBA();
          if (audioFrame != null) {
            int sampleCount = widget.sampleRate ~/ fps;

            audioFinal = convertPcmToWav(
                convertBytesToInt16(audioFrame!),
                sampleRate: widget.sampleRate,
                numChannels: widget.audioChannels,
            ).sublist(audioFrame!.length - sampleCount * bytesPerSample * widget.audioChannels);
            // audioFinal = audioFrame!.sublist(audioFrame!.length - (widget.sampleRate * widget.audioChannels * 2) ~/ FlutterQuickVideoEncoder.fps);
          }

          await readyForMore.future;
          readyForMore = Completer<void>();

          try {
            _appendFrames(videoFrame, audioFinal)
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

      record.dispose();
      await FlutterQuickVideoEncoder.finish();
      int endTime = DateTime.now().millisecondsSinceEpoch;
      int videoTime = ((endTime - startTime) / 1000).round() - 1;
      debugPrint("video time: $videoTime");

      widget.onComplete(FlutterQuickVideoEncoder.filepath);

      FlutterQuickVideoEncoder.finish();
    } catch (e) {
      ('Error: $e');
    }
  }

  Future<Uint8List?> captureWidgetAsRGBA() async {
    try {
      RenderRepaintBoundary boundary =
      recordKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: widget.pixelRatio);
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
    if (videoFrame != null && audioFrame != null) {
      await FlutterQuickVideoEncoder.appendVideoFrame(videoFrame);
      await FlutterQuickVideoEncoder.appendAudioFrame(audioFrame);
    } else {
      debugPrint("Error append add frame");
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
    return RepaintBoundary(
      key: recordKey,
      child: widget.child,
    );
  }
}
