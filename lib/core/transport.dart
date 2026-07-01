import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:rust_api/rust_api.dart';

// ── Binary frame types (mirrors Rust ipc.rs) ────────────────────────────────

const _typeReady = 0x00;
const _typeConnected = 0x01;
const _typeDisconnected = 0x02;
const _typeData = 0x03;
const _typeError = 0x04;

class OhosDisconnectGate {
  int _generation = 0;
  int? _activeGeneration;
  bool _didNotifyDisconnect = false;

  int beginConnection() {
    _generation += 1;
    _activeGeneration = _generation;
    _didNotifyDisconnect = false;
    return _generation;
  }

  bool consumeDisconnect(int generation) {
    if (_activeGeneration != generation || _didNotifyDisconnect) {
      return false;
    }
    _activeGeneration = null;
    _didNotifyDisconnect = true;
    return true;
  }

  bool isActiveConnection(int generation) => _activeGeneration == generation;

  void reset() {
    _activeGeneration = null;
    _didNotifyDisconnect = false;
  }
}

class IPCCoreTransport {
  final String address;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>();
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<Uint8List>? _socketSubscription;
  Completer<void> _completer = Completer<void>();
  Completer<void> _readyCompleter = Completer<void>();
  ServerSocket? _serverSocket;
  Socket? _socket;
  final BytesBuilder _frameBuffer = BytesBuilder(copy: false);
  final OhosDisconnectGate _ohosDisconnectGate = OhosDisconnectGate();
  int? _activeOhosConnectionGeneration;

  void Function()? onDisconnect;

  IPCCoreTransport({required this.address});

  Completer<void> get connectionCompleter => _completer;

  Completer<void> get readyCompleter => _readyCompleter;

  Stream<Uint8List> get dataStream => _dataController.stream;

  Future<void> init() async {
    if (system.isOhos) {
      await _initOhosSocketServer();
      return;
    }
    try {
      final stream = restartIpcServer(name: address);
      _subscription = stream.listen(
        (data) {
          if (data.isEmpty) return;
          final type = data[0];
          final payload = data.length > 1 ? data.sublist(1) : Uint8List(0);
          switch (type) {
            case _typeReady:
              commonPrint.log('IPC Ready');
              if (_readyCompleter.isCompleted) {
                break;
              }
              _readyCompleter.complete();
              break;
            case _typeConnected:
              commonPrint.log('IPC Connected');
              if (_completer.isCompleted) {
                break;
              }
              _completer.complete();
              break;
            case _typeDisconnected:
              commonPrint.log('IPC Disconnected');
              _completer = Completer<void>();
              onDisconnect?.call();
              break;
            case _typeData:
              _dataController.add(payload);
              break;
            case _typeError:
              final msg = utf8.decode(payload);
              commonPrint.log('IPC error: $msg', logLevel: LogLevel.error);
              break;
            default:
              commonPrint.log(
                'IPC unknown frame type: $type',
                logLevel: LogLevel.warning,
              );
          }
        },
        onError: (error) {
          commonPrint.log('IPC error: $error', logLevel: LogLevel.error);
        },
        cancelOnError: false,
      );
      await _readyCompleter.future;
    } catch (e) {
      commonPrint.log(
        'Failed to start IPC server: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  void send(String message) {
    if (system.isOhos) {
      _sendOhosFrame(utf8.encode(message));
      return;
    }
    sendIpcMessage(data: utf8.encode(message));
  }

  void disconnected() {
    _completer = Completer<void>();
  }

  Future<void> disconnect() async {
    final generation = _activeOhosConnectionGeneration;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
    _frameBuffer.clear();
    if (generation != null) {
      _handleOhosDisconnect(generation);
    } else {
      _ohosDisconnectGate.reset();
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
    await _serverSocket?.close();
    _serverSocket = null;
    if (!system.isOhos) {
      await stopIpcServer();
    }
    _activeOhosConnectionGeneration = null;
    _ohosDisconnectGate.reset();
    _readyCompleter = Completer<void>();
    _completer = Completer<void>();
    if (!_dataController.isClosed) {
      await _dataController.close();
    }
  }

  Future<void> _initOhosSocketServer() async {
    try {
      final path = address;
      final socketFile = File(path);
      if (await socketFile.exists()) {
        await socketFile.safeDelete();
      }
      await socketFile.parent.create(recursive: true);
      _serverSocket = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        shared: false,
      );
      commonPrint.log('IPC Ready');
      _readyCompleter.safeCompleter(null);
      _serverSocket!.listen((socket) async {
        final generation = _ohosDisconnectGate.beginConnection();
        _activeOhosConnectionGeneration = generation;
        final previousSubscription = _socketSubscription;
        final previousSocket = _socket;
        _socket = socket;
        _socketSubscription = null;
        await previousSubscription?.cancel();
        await previousSocket?.close();
        commonPrint.log('IPC Connected');
        _completer.safeCompleter(null);
        _socketSubscription = socket.listen(
          _handleOhosSocketData,
          onDone: () => _handleOhosDisconnect(generation),
          onError: (error) {
            commonPrint.log('IPC error: $error', logLevel: LogLevel.error);
            _handleOhosDisconnect(generation);
          },
          cancelOnError: false,
        );
      });
    } catch (e) {
      commonPrint.log(
        'Failed to start IPC server: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  void _handleOhosSocketData(Uint8List data) {
    _frameBuffer.add(data);
    final bytes = _frameBuffer.toBytes();
    var offset = 0;
    while (bytes.length - offset >= 4) {
      final length = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0, Endian.little);
      if (bytes.length - offset - 4 < length) {
        break;
      }
      final payload = Uint8List.sublistView(
        bytes,
        offset + 4,
        offset + 4 + length,
      );
      _dataController.add(payload);
      offset += 4 + length;
    }
    if (offset == 0) {
      return;
    }
    final remaining = bytes.sublist(offset);
    _frameBuffer.clear();
    if (remaining.isNotEmpty) {
      _frameBuffer.add(remaining);
    }
  }

  void _sendOhosFrame(List<int> data) {
    final socket = _socket;
    if (socket == null) {
      commonPrint.log('IPC send skipped: socket not connected');
      return;
    }
    final header = ByteData(4)..setUint32(0, data.length, Endian.little);
    socket.add(header.buffer.asUint8List());
    socket.add(data);
  }

  void _handleOhosDisconnect(int generation) {
    if (!_ohosDisconnectGate.consumeDisconnect(generation)) {
      return;
    }
    commonPrint.log('IPC Disconnected');
    _completer = Completer<void>();
    _socket = null;
    _socketSubscription = null;
    _frameBuffer.clear();
    if (_activeOhosConnectionGeneration == generation) {
      _activeOhosConnectionGeneration = null;
    }
    onDisconnect?.call();
  }
}
