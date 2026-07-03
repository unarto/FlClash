const { harTasks, prepareNativePluginModule } = require('../../../ohos/hvigor/plugin-loader');

prepareNativePluginModule(__dirname);

export default {
  system: harTasks,
  plugins: []
}
