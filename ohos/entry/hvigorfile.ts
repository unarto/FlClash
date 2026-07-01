
// Script for compiling build behavior. It is built in the build plug-in and cannot be modified currently.
const { hapTasks } = require('../hvigor/plugin-loader');

export default {
    system: hapTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[]         /* Custom plugin to extend the functionality of Hvigor. */
}
