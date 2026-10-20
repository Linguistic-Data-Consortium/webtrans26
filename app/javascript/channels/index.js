// loads all '*_channel.js' channels within the directory

// load all channels
const channels = require.context(".", true, /_channel\.js$/);
channels.keys().forEach(channels);
