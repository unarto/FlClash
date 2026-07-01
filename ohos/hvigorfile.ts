import path from 'path';

const {
  appTasks,
  loadFlutterHvigorPlugin,
} = require('./hvigor/plugin-loader');
const { flutterHvigorPlugin } = loadFlutterHvigorPlugin();

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[flutterHvigorPlugin(path.dirname(__dirname))]         /* Custom plugin to extend the functionality of Hvigor. */
}
