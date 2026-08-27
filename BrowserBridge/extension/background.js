const NATIVE_HOST = "com.nodebay.browser_bridge";
const EXTENSION_VERSION = chrome.runtime.getManifest().version;
let nativePort = null;
let reconnectTimer = null;

function connectNative() {
  if (nativePort) return nativePort;
  try {
    nativePort = chrome.runtime.connectNative(NATIVE_HOST);
    nativePort.onMessage.addListener(handleNativeMessage);
    nativePort.onDisconnect.addListener(() => {
      nativePort = null;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      reconnectTimer = setTimeout(connectNative, 3000);
    });
    nativePort.postMessage({ type: "hello", extensionVersion: EXTENSION_VERSION });
  } catch (_error) {
    nativePort = null;
  }
  return nativePort;
}

function sendNative(message) {
  const port = connectNative();
  if (!port) return;
  try {
    port.postMessage(message);
  } catch (_error) {
    nativePort = null;
  }
}

function supportedURL(url) {
  return typeof url === "string" && (
    url.startsWith("https://www.youtube.com/") ||
    url.startsWith("https://music.youtube.com/")
  );
}

chrome.runtime.onMessage.addListener((message, sender) => {
  if (!sender.tab || !Number.isInteger(sender.tab.id) || !supportedURL(sender.tab.url)) return;
  const id = `chrome:${sender.tab.id}`;
  if (message?.type === "nodebay-media-state" && message.available === true) {
    sendNative({
      type: "tabState",
      session: { ...message.session, tabID: sender.tab.id, pageURL: sender.tab.url }
    });
  } else if (message?.type === "nodebay-media-state" && message.available === false) {
    sendNative({ type: "tabRemoved", id });
  }
});

chrome.tabs.onRemoved.addListener((tabID) => {
  sendNative({ type: "tabRemoved", id: `chrome:${tabID}` });
});

function handleNativeMessage(message) {
  if (message?.type !== "command" || !Number.isInteger(message.tabId)) return;
  const allowedActions = new Set(["play", "pause", "togglePlay", "seek", "setVolume", "next", "previous"]);
  if (!allowedActions.has(message.action)) return;
  chrome.tabs.sendMessage(message.tabId, {
    type: "nodebay-command",
    action: message.action,
    value: message.value
  }).catch(() => {
    sendNative({ type: "tabRemoved", id: `chrome:${message.tabId}` });
  });
}

chrome.runtime.onInstalled.addListener(() => {
  connectNative();
  chrome.tabs.query({
    url: ["https://www.youtube.com/*", "https://music.youtube.com/*"]
  }).then((tabs) => {
    for (const tab of tabs) {
      if (Number.isInteger(tab.id) && supportedURL(tab.url)) {
        chrome.tabs.sendMessage(tab.id, { type: "nodebay-probe" }).catch(() => {});
      }
    }
  });
});

chrome.runtime.onStartup.addListener(connectNative);
connectNative();
