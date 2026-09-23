const NATIVE_HOST = "com.nodebay.browser_bridge";
const EXTENSION_VERSION = chrome.runtime.getManifest().version;
let nativePort = null;
let reconnectTimer = null;
let allMediaEnabled = false;
let mediaAccessSync = null;
const equalizedTabs = new Set();
const genericMediaTabs = new Set();
const OFFSCREEN_PATH = "offscreen.html";
const ALL_MEDIA_PERMISSION = { origins: ["http://*/*", "https://*/*"] };
const ALL_MEDIA_SCRIPT = "nodebay-all-media";
const YOUTUBE_URLS = ["https://www.youtube.com/*", "https://music.youtube.com/*"];

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
  if (typeof url !== "string") return false;
  try { return ["http:", "https:"].includes(new URL(url).protocol); }
  catch (_error) { return false; }
}

function isYouTubeURL(url) {
  return typeof url === "string" && (
    url.startsWith("https://www.youtube.com/") || url.startsWith("https://music.youtube.com/")
  );
}

function syncAllMediaAccess() {
  if (mediaAccessSync) return mediaAccessSync;
  mediaAccessSync = performMediaAccessSync().finally(() => { mediaAccessSync = null; });
  return mediaAccessSync;
}

async function performMediaAccessSync() {
  const allowed = await chrome.permissions.contains(ALL_MEDIA_PERMISSION);
  allMediaEnabled = allowed;
  const registered = await chrome.scripting.getRegisteredContentScripts({ ids: [ALL_MEDIA_SCRIPT] });
  if (allowed && registered.length === 0) {
    await chrome.scripting.registerContentScripts([{
      id: ALL_MEDIA_SCRIPT,
      matches: ALL_MEDIA_PERMISSION.origins,
      excludeMatches: YOUTUBE_URLS,
      js: ["media.js"],
      runAt: "document_idle",
      persistAcrossSessions: true
    }]);
  } else if (!allowed && registered.length > 0) {
    await chrome.scripting.unregisterContentScripts({ ids: [ALL_MEDIA_SCRIPT] });
  }
  if (!allowed) {
    for (const tabID of genericMediaTabs) {
      sendNative({ type: "tabRemoved", id: `chrome:${tabID}` });
    }
    genericMediaTabs.clear();
  }
  if (allowed) {
    const tabs = await chrome.tabs.query({ url: ALL_MEDIA_PERMISSION.origins });
    await Promise.all(tabs.filter((tab) => Number.isInteger(tab.id) && supportedURL(tab.url) && !isYouTubeURL(tab.url))
      .map(async (tab) => {
        await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["media.js"] }).catch(() => {});
        probeTab(tab.id);
      }));
  }
  return allowed;
}

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message?.target === "nodebay-background" && message.type === "eqStopped" && Number.isInteger(message.tabID)) {
    equalizedTabs.delete(message.tabID);
    probeTab(message.tabID);
    return;
  }

  if (message?.type === "nodebay-popup-status") {
    const tabID = message.tabID;
    return chrome.permissions.contains(ALL_MEDIA_PERMISSION).then((allMediaEnabled) => ({
      enabled: Number.isInteger(tabID) && equalizedTabs.has(tabID), allMediaEnabled
    }));
  }

  if (message?.type === "nodebay-refresh-all-media") {
    return syncAllMediaAccess().then((enabled) => ({ ok: enabled }))
      .catch((error) => ({ ok: false, error: error?.message }));
  }

  if (message?.type === "nodebay-enable-eq") {
    return enableEqualizer(message.tabID);
  }

  if (message?.type === "nodebay-disable-eq") {
    return stopEqualizer(message.tabID).then(() => ({ ok: true }));
  }

  if (!sender.tab || !Number.isInteger(sender.tab.id) || !supportedURL(sender.tab.url)) return;
  if (!isYouTubeURL(sender.tab.url) && !allMediaEnabled) return;
  const id = `chrome:${sender.tab.id}`;
  if (!isYouTubeURL(sender.tab.url)) genericMediaTabs.add(sender.tab.id);
  if (message?.type === "nodebay-media-state" && message.available === true) {
    sendNative({
      type: "tabState",
      session: {
        ...message.session,
        tabID: sender.tab.id,
        pageURL: isYouTubeURL(sender.tab.url) ? sender.tab.url : null,
        eqEnabled: equalizedTabs.has(sender.tab.id)
      }
    });
  } else if (message?.type === "nodebay-media-state" && message.available === false) {
    genericMediaTabs.delete(sender.tab.id);
    sendNative({ type: "tabRemoved", id });
  }
});

chrome.tabs.onRemoved.addListener((tabID) => {
  if (equalizedTabs.has(tabID)) stopEqualizer(tabID);
  genericMediaTabs.delete(tabID);
  sendNative({ type: "tabRemoved", id: `chrome:${tabID}` });
});

chrome.tabs.onUpdated.addListener((tabID, changeInfo) => {
  if (changeInfo.status === "loading" || changeInfo.url) {
    genericMediaTabs.delete(tabID);
    sendNative({ type: "tabRemoved", id: `chrome:${tabID}` });
  }
});

chrome.permissions.onAdded.addListener(() => { syncAllMediaAccess().catch(() => {}); });
chrome.permissions.onRemoved.addListener(() => { syncAllMediaAccess().catch(() => {}); });

function probeTab(tabID) {
  if (!Number.isInteger(tabID)) return;
  chrome.tabs.sendMessage(tabID, { type: "nodebay-probe" }).catch(() => {});
}

async function enableEqualizer(tabID) {
  if (!Number.isInteger(tabID)) return { ok: false, error: "No active tab was selected." };
  const tab = await chrome.tabs.get(tabID).catch(() => null);
  if (!tab || !isYouTubeURL(tab.url)) {
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
  syncAllMediaAccess().catch(() => {});
  chrome.tabs.query({ url: YOUTUBE_URLS }).then((tabs) => {
    for (const tab of tabs) {
      if (Number.isInteger(tab.id) && isYouTubeURL(tab.url)) {
        chrome.tabs.sendMessage(tab.id, { type: "nodebay-probe" }).catch(() => {});
      }
    }
  });
});

chrome.runtime.onStartup.addListener(() => { connectNative(); syncAllMediaAccess().catch(() => {}); });
connectNative();
syncAllMediaAccess().catch(() => {});
