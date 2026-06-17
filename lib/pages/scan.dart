import 'dart:async';
import 'dart:math';

import 'package:fl_clash/common/color.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/activate_box.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  // 1. 改变检测速度为默认或正常，允许连续识别
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal, 
    formats: const [BarcodeFormat.qrCode],
  );

  StreamSubscription<Object?>? _subscription;
  bool _isPopping = false; // 防止多次重复触发 pop

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startScanning();
  }

  // 提取启动和监听逻辑，避免重复写
  void _startScanning() {
    if (_subscription != null) return; // 确保不重复监听
    _subscription = controller.barcodes.listen(_handleBarcode);
    unawaited(controller.start());
  }

  void _stopScanning() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(controller.stop());
  }

  void _handleBarcode(BarcodeCapture barcodeCapture) {
    if (_isPopping || barcodeCapture.barcodes.isEmpty) return;
    
    final barcode = barcodeCapture.barcodes.first;
    final rawValue = barcode.rawValue;
    
    if (rawValue == null || rawValue.isEmpty) return;

    _isPopping = true; // 锁死状态，防止重复 pop
    
    // 很多二维码内容并不是标准的 URL 格式（可能只是普通字符串）
    // 如果你只需要拿到二维码里的文本，直接返回原始值即可，不用强求 BarcodeType.url
    if (barcode.type == BarcodeType.url || rawValue.startsWith('http')) {
      Navigator.pop<String>(context, rawValue);
    } else {
      // 如果不是 URL，也返回原始文本，由调用方决定怎么处理
      Navigator.pop<String>(context, rawValue);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.resumed:
        _startScanning(); // 使用封装好的安全启动
        break;
      case AppLifecycleState.inactive:
        _stopScanning(); // 使用封装好的安全停止
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double sideLength = min(400, MediaQuery.of(context).size.width * 0.67);
    final scanWindow = Rect.fromCenter(
      center: MediaQuery.sizeOf(context).center(Offset.zero),
      width: sideLength,
      height: sideLength,
    );
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: MobileScanner(
              controller: controller,
              scanWindow: scanWindow,
            ),
          ),
          CustomPaint(painter: ScannerOverlay(scanWindow: scanWindow)),
          AppBar(
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            leading: IconButton(
              style: IconButton.styleFrom(
                iconSize: 32,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.close),
            ),
            actions: [
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: controller,
                builder: (context, state, _) {
                  var icon = const Icon(Icons.flash_off);
                  var backgroundColor = Colors.black12;
                  switch (state.torchState) {
                    case TorchState.off:
                      icon = const Icon(Icons.flash_off);
                      backgroundColor = Colors.black12;
                    case TorchState.on:
                      icon = const Icon(Icons.flash_on);
                      backgroundColor = Colors.orange;
                    case TorchState.unavailable:
                      icon = const Icon(Icons.flash_off);
                      backgroundColor = Colors.transparent;
                    case TorchState.auto:
                      icon = const Icon(Icons.flash_auto);
                      backgroundColor = Colors.orange;
                  }
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: ActivateBox(
                      active: state.torchState != TorchState.unavailable,
                      child: IconButton(
                        color: Colors.white,
                        icon: icon,
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: backgroundColor,
                        ),
                        onPressed: () => controller.toggleTorch(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 32),
            alignment: Alignment.bottomCenter,
            child: IconButton(
              color: Colors.white,
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.grey,
              ),
              padding: const EdgeInsets.all(16),
              iconSize: 32.0,
              onPressed: globalState.container
                  .read(profilesActionProvider.notifier)
                  .addProfileFormQrCode,
              icon: const Icon(Icons.photo_camera_back),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _stopScanning();
    await controller.dispose();
    super.dispose();
  }
}

class ScannerOverlay extends CustomPainter {
  const ScannerOverlay({required this.scanWindow, this.borderRadius = 12.0});

  final Rect scanWindow;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()..addRect(Rect.largest);

    final cutoutPath = Path()
      ..addRSuperellipse(
        RSuperellipse.fromRectAndCorners(
          scanWindow,
          topLeft: Radius.circular(borderRadius),
          topRight: Radius.circular(borderRadius),
          bottomLeft: Radius.circular(borderRadius),
          bottomRight: Radius.circular(borderRadius),
        ),
      );

    final backgroundPaint = Paint()
      ..color = Colors.black.opacity50
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.dstOut;

    final backgroundWithCutout = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final border = RSuperellipse.fromRectAndCorners(
      scanWindow,
      topLeft: Radius.circular(borderRadius),
      topRight: Radius.circular(borderRadius),
      bottomLeft: Radius.circular(borderRadius),
      bottomRight: Radius.circular(borderRadius),
    );

    canvas.drawPath(backgroundWithCutout, backgroundPaint);
    canvas.drawRSuperellipse(border, borderPaint);
  }

  @override
  bool shouldRepaint(ScannerOverlay oldDelegate) {
    return scanWindow != oldDelegate.scanWindow ||
        borderRadius != oldDelegate.borderRadius;
  }
}
