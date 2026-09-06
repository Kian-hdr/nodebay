const processors = new Map();
const frequencies = [60, 250, 1000, 4000, 12000];

function clampGain(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(-12, Math.min(6, number)) : 0;
}

async function stop(tabID) {
  const processor = processors.get(tabID);
  if (!processor) return;
  processors.delete(tabID);
  processor.stream.getTracks().forEach((track) => track.stop());
  await processor.context.close().catch(() => {});
}

async function start(tabID, streamID) {
  await stop(tabID);
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      mandatory: {
        chromeMediaSource: "tab",
        chromeMediaSourceId: streamID
      }
    },
    video: false
  });

  const context = new AudioContext({ latencyHint: "interactive" });
  const source = context.createMediaStreamSource(stream);
  const bands = frequencies.map((frequency) => {
    const filter = context.createBiquadFilter();
    filter.type = "peaking";
    filter.frequency.value = frequency;
    filter.Q.value = 1;
    filter.gain.value = 0;
    return filter;
  });
  const headroom = context.createGain();
  source.connect(bands[0]);
  for (let index = 0; index < bands.length - 1; index += 1) {
    bands[index].connect(bands[index + 1]);
  }
  bands[bands.length - 1].connect(headroom);
  headroom.connect(context.destination);
  stream.getAudioTracks().forEach((track) => {
    track.addEventListener("ended", () => {
      stop(tabID);
      chrome.runtime.sendMessage({ target: "nodebay-background", type: "eqStopped", tabID }).catch(() => {});
    }, { once: true });
  });
  processors.set(tabID, { context, stream, bands, headroom, values: [0, 0, 0, 0, 0] });
  await context.resume();
}

function setEqualizer(tabID, values, bypassed) {
  const processor = processors.get(tabID);
  if (!processor || !Array.isArray(values) || values.length !== frequencies.length) return false;
  const gains = values.map(clampGain);
  processor.values = gains;
  const applied = bypassed ? gains.map(() => 0) : gains;
  applied.forEach((gain, index) => {
    processor.bands[index].gain.setTargetAtTime(gain, processor.context.currentTime, 0.01);
  });
  const maximumBoost = Math.max(0, ...applied);
  processor.headroom.gain.setTargetAtTime(Math.pow(10, -maximumBoost / 20), processor.context.currentTime, 0.01);
  return true;
}

chrome.runtime.onMessage.addListener((message) => {
  if (message?.target !== "nodebay-offscreen") return;
  if (message.type === "startEQ") {
    return start(message.tabID, message.streamID)
      .then(() => ({ ok: true }))
      .catch((error) => ({ ok: false, error: error?.message || "Audio capture failed." }));
  }
  if (message.type === "setEQ") {
    return Promise.resolve({ ok: setEqualizer(message.tabID, message.values, message.bypassed === true) });
  }
  if (message.type === "stopEQ") {
    return stop(message.tabID).then(() => ({ ok: true }));
  }
});
