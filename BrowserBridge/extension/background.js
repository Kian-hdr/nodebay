const NATIVE_HOST = "com.nodebay.browser_bridge";
const EXTENSION_VERSION = chrome.runtime.getManifest().version;
let nativePort = null;
let reconnectTimer = null;
const equalizedTabs = new Set();
const OFFSCREEN_PATH = "offscreen.html";

async function ensureOffscreenDocument() {
  const offscreenURL = chrome.runtime.getURL(OFFSCREEN_PATH);
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ["OFFSCREEN_DOCUMENT"],
    documentUrls: [offscreenURL]
  });
  if (contexts.length > 0) return;
  await chrome.offscreen.createDocument({
    url: OFFSCREEN_PATH,
    reasons: ["USER_MEDIA"],
    justification: "Process audio from a user-enabled tab with the local Nodebay equalizer."
  });
}

async function stopEqualizer(tabID) {
  if (!Number.isInteger(tabID)) return;
  try {
    await ensureOffscreenDocument();
    await chrome.runtime.sendMessage({ target: "nodebay-offscreen", type: "stopEQ", tabID });
  } catch (_error) {}
  equalizedTabs.delete(tabID);
  probeTab(tabID);
}

async function stopAllEqualizers() {
  const tabs = [...equalizedTabs];
  await Promise.all(tabs.map(stopEqualizer));
}

function connectNative() {
  if (nativePort) return nativePort;
  try {
    nativePort = chrome.runtime.connectNative(NATIVE_HOST);
    nativePort.onMessage.addListener(handleNativeMessage);
    nativePort.onDisconnect.addListener(() => {
      nativePort = null;
      stopAllEqualizers();
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
  if (message?.target === "nodebay-background" && message.type === "eqStopped" && Number.isInteger(message.tabID)) {
    equalizedTabs.delete(message.tabID);
    probeTab(message.tabID);
    return;
  }

  if (message?.type === "nodebay-popup-status") {
    const tabID = message.tabID;
    return Promise.resolve({ enabled: Number.isInteger(tabID) && equalizedTabs.has(tabID) });
  }

  if (message?.type === "nodebay-enable-eq") {
    return enableEqualizer(message.tabID);
  }

  if (message?.type === "nodebay-disable-eq") {
    return stopEqualizer(message.tabID).then(() => ({ ok: true }));
  }

  if (!sender.tab || !Number.isInteger(sender.tab.id) || !supportedURL(sender.tab.url)) return;
  const id = `chrome:${sender.tab.id}`;
  if (message?.type === "nodebay-media-state" && message.available === true) {
    sendNative({
      type: "tabState",
      session: {
        ...message.session,
        tabID: sender.tab.id,
        pageURL: sender.tab.url,
        eqEnabled: equalizedTabs.has(sender.tab.id)
      }
    });
  } else if (message?.type === "nodebay-media-state" && message.available === false) {
    sendNative({ type: "tabRemoved", id });
  }
});

chrome.tabs.onRemoved.addListener((tabID) => {
  stopEqualizer(tabID);
  sendNative({ type: "tabRemoved", id: `chrome:${tabID}` });
});

function probeTab(tabID) {
  if (!Number.isInteger(tabID)) return;
  chrome.tabs.sendMessage(tabID, { type: "nodebay-probe" }).catch(() => {});
}

async function enableEqualizer(tabID) {
  if (!Number.isInteger(tabID)) return { ok: false, error: "No active tab was selected." };
  const tab = await chrome.tabs.get(tabID).catch(() => null);
  if (!tab || !supportedURL(tab.url)) {
    return { ok: false, error: "Open a YouTube or YouTube Music tab first." };
  }
  if (equalizedTabs.has(tabID)) return { ok: true, enabled: true };

  try {
    await ensureOffscreenDocument();
    const streamID = await chrome.tabCapture.getMediaStreamId({ targetTabId: tabID });
    const result = await chrome.runtime.sendMessage({
      target: "nodebay-offscreen",
      type: "startEQ",
      tabID,
      streamID
    });
    if (!result?.ok) throw new Error(result?.error || "Audio capture could not start.");
    equalizedTabs.add(tabID);
    probeTab(tabID);
    return { ok: true, enabled: true };
  } catch (error) {
    equalizedTabs.delete(tabID);
    return { ok: false, error: error?.message || "Audio capture could not start." };
  }
}

function handleNativeMessage(message) {
  if (message?.type !== "command" || !Number.isInteger(message.tabId)) return;
  if (message.action === "setEQ") {
    if (!equalizedTabs.has(message.tabId)) return;
    chrome.runtime.sendMessage({
      target: "nodebay-offscreen",
      type: "setEQ",
      tabID: message.tabId,
      values: message.values,
      bypassed: message.bypassed === true
    }).catch(() => stopEqualizer(message.tabId));
    return;
  }
  if (message.action === "disableEQ") {
    stopEqualizer(message.tabId);
    return;
  }
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
