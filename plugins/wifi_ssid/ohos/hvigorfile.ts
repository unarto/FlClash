// Script for compiling build behavior. It is built in the build plug-in and cannot be modified currently.
const { harTasks, prepareNativePluginModule } = require('../../../ohos/hvigor/plugin-loader');

prepareNativePluginModule(__dirname);

export default {
  system: harTasks,
  plugins: []
}
