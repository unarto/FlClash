import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

export default class ProxyPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'ProxyPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'proxy');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'StartProxy':
      case 'StopProxy':
        result.success(false);
        break;
      default:
        result.notImplemented();
        break;
    }
  }
}
