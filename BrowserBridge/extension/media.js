(() => {
  if (globalThis.__nodebayMediaBridgeInstalled) return;
  globalThis.__nodebayMediaBridgeInstalled = true;

  let lastPayload = "";
  let lastSentAt = 0;

  function text(selector) {
    return document.querySelector(selector)?.textContent?.trim() || "";
  }

  function finite(value, fallback = 0) {
    return Number.isFinite(value) ? value : fallback;
  }

  function mediaElement() {
    const candidates = [...document.querySelectorAll("video, audio")];
    return candidates.find((item) => item.duration > 0 || !item.paused) || candidates[0] || null;
  }

  function metadata() {
    const isMusic = location.hostname === "music.youtube.com";
    const media = mediaElement();
    if (!media) return null;

    const title = isMusic
      ? text("ytmusic-player-bar .title")
      : text("h1 yt-formatted-string") || document.title.replace(/\s+-\s+YouTube$/, "");
    const artist = isMusic
      ? text("ytmusic-player-bar .byline")
      : text("#owner #channel-name a") || document.querySelector('meta[name="author"]')?.content || "";

    return {
      siteName: isMusic ? "YouTube Music" : "YouTube",
      title,
      artist,
      isPlaying: !media.paused && !media.ended,
      currentTime: finite(media.currentTime),
      duration: finite(media.duration),
      playbackRate: finite(media.playbackRate, 1),
      volume: finite(media.volume, 1),
      isMuted: media.muted,
      canSeek: Number.isFinite(media.duration) && media.duration > 0,
      canGoNext: Boolean(document.querySelector(".ytp-next-button, .next-button.ytmusic-player-bar")),
      canGoPrevious: Boolean(document.querySelector(".previous-button.ytmusic-player-bar"))
    };
  }

  function publish(force = false) {
    const session = metadata();
    const payload = JSON.stringify(session);
    const now = Date.now();
    if (!force && payload === lastPayload && now - lastSentAt < 5000) return;
    lastPayload = payload;
    lastSentAt = now;
    chrome.runtime.sendMessage({
      type: "nodebay-media-state",
      available: Boolean(session),
      session
    }).catch(() => {});
  }

  async function runCommand(message) {
    const media = mediaElement();
    if (!media) return;
    switch (message.action) {
      case "play":
        await media.play().catch(() => {});
        break;
      case "pause":
        media.pause();
        break;
      case "togglePlay":
        if (media.paused) await media.play().catch(() => {});
        else media.pause();
        break;
      case "seek":
        if (Number.isFinite(message.value) && Number.isFinite(media.duration)) {
          media.currentTime = Math.max(0, Math.min(media.duration, message.value));
        }
        break;
      case "setVolume":
        if (Number.isFinite(message.value)) {
          media.volume = Math.max(0, Math.min(1, message.value));
          media.muted = false;
        }
        break;
      case "next":
        document.querySelector(".ytp-next-button, .next-button.ytmusic-player-bar")?.click();
        break;
      case "previous":
        document.querySelector(".previous-button.ytmusic-player-bar")?.click();
        break;
    }
    publish(true);
  }

  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "nodebay-command") runCommand(message);
    if (message?.type === "nodebay-probe") publish(true);
  });

  for (const eventName of ["play", "pause", "ended", "durationchange", "volumechange", "ratechange", "loadedmetadata"]) {
    document.addEventListener(eventName, () => publish(true), true);
  }
  new MutationObserver(() => publish()).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(() => publish(), 1000);
  publish(true);
})();
