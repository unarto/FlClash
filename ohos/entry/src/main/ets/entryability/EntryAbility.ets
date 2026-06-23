
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import AppPlugin from '../plugins/AppPlugin';

export default class EntryAbility extends FlutterAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    AppPlugin.setPendingLinkFromWant(want)
    super.onCreate(want, launchParam)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    AppPlugin.setPendingLinkFromWant(want)
    super.onNewWant(want, launchParam)
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
