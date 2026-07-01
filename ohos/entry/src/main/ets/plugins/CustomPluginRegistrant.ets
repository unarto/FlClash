import { FlutterEngine, Log } from '@ohos/flutter_ohos';
import AppPlugin from './AppPlugin';
import FilePickerPlugin from './FilePickerPlugin';
import { stringifyError } from './error_utils';

const TAG = 'CustomPluginRegistrant';

export class CustomPluginRegistrant {
  static registerWith(flutterEngine: FlutterEngine) {
    try {
      const plugins = flutterEngine.getPlugins();
      if (plugins == null) {
        return;
      }
      if (!plugins.has('AppPlugin')) {
        plugins.add(new AppPlugin());
      }
      if (!plugins.has('FilePickerPlugin')) {
        plugins.add(new FilePickerPlugin());
      }
    } catch (e) {
      Log.e(
        TAG,
        'Tried to register custom plugins with FlutterEngine ('
          + flutterEngine
          + ') failed.',
      );
      Log.e(
        TAG,
        `Received exception while registering: ${stringifyError(e)}`,
      );
    }
  }
}
