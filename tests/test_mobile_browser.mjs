import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

function target() {
  const listeners = new Map();
  return {
    addEventListener(type, callback) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(callback);
    },
    dispatch(type, event = {}) {
      for (const callback of listeners.get(type) || []) callback(event);
    },
  };
}

function browser(permission, active = true) {
  const window = target();
  const document = target();
  const buttons = [];
  const canvas = { getBoundingClientRect: () => ({ left: 0, top: 0, width: 800, height: 400 }) };
  document.hidden = false;
  document.activeElement = null;
  document.elementFromPoint = () => null;
  document.getElementById = (id) => id === "canvas" ? canvas : null;
  document.createElement = () => {
    const button = target();
    button.style = {};
    button.dataset = {};
    button.setAttribute = () => {};
    button.setPointerCapture = () => {};
    buttons.push(button);
    return button;
  };
  document.body = { appendChild: () => {} };
  window.isSecureContext = true;
  window.DeviceOrientationEvent = { requestPermission: permission };
  window.scrollTo = () => {};
  let resizeCount = 0;
  window.dispatchEvent = () => { resizeCount += 1; };
  let now = 1000;
  const timers = [];
  const context = {
    window, document, DeviceOrientationEvent: window.DeviceOrientationEvent,
    navigator: { userActivation: { isActive: active } },
    screen: { orientation: { angle: 0 } },
    Date: { now: () => now }, Event: class {}, setTimeout: (callback) => { timers.push(callback); },
  };
  runInNewContext(readFileSync(new URL("../tools/mobile-browser.js", import.meta.url), "utf8"), context);
  runInNewContext(readFileSync(new URL("../tools/mobile-sensors.js", import.meta.url), "utf8"), context);
  return { window, document, buttons, setNow: (value) => { now = value; }, runTimers: () => {
    for (const callback of timers.splice(0)) callback();
  }, resizeCount: () => resizeCount };
}

const env = browser(() => Promise.resolve("granted"));
env.window.EVW_INPUT.setButton("gas", 0.75, 0.5, 0.2, 0.3);
env.window.EVW_INPUT.setButton("left", 0.05, 0.5, 0.2, 0.3);
env.window.EVW_INPUT.setButton("calibrate", 0.25, 0.3, 0.5, 0.1);
const gas = env.buttons.find((button) => button.dataset.evwControl === "gas");
const left = env.buttons.find((button) => button.dataset.evwControl === "left");
const calibrate = env.buttons.find((button) => button.dataset.evwControl === "calibrate");
env.document.elementFromPoint = (x) => x > 500 ? gas : x < 200 ? left : calibrate;
gas.dispatch("pointerdown", { pointerId: 3, preventDefault() {} });
left.dispatch("pointerdown", { pointerId: 9, preventDefault() {} });
assert.equal(env.window.EVW_INPUT.pressed("gas"), 1);
assert.equal(env.window.EVW_INPUT.pressed("left"), 1);
env.document.dispatch("pointerup", { pointerId: 3, clientX: 600, clientY: 300 });
assert.equal(env.window.EVW_INPUT.pressed("gas"), 0, "pedal releases on pointerup");
assert.equal(env.window.EVW_INPUT.pressed("left"), 1, "other finger stays pressed");
env.document.dispatch("pointercancel", { pointerId: 9 });
assert.equal(env.window.EVW_INPUT.pressed("left"), 0, "steering releases on pointercancel");
calibrate.dispatch("pointerdown", { pointerId: 11, preventDefault() {} });
env.document.dispatch("pointerup", { pointerId: 11, clientX: 400, clientY: 150 });
assert.equal(env.window.EVW_INPUT.takeCommand(), "calibrate", "calibration button queues a tap");
gas.dispatch("pointerdown", { pointerId: 12, preventDefault() {} });
env.window.dispatch("blur");
assert.equal(env.window.EVW_INPUT.pressed("gas"), 0, "blur releases controls");
const keyboard = { tagName: "INPUT", style: { zIndex: "-1" } };
env.document.dispatch("focusin", { target: keyboard });
env.document.dispatch("focusout", { target: keyboard });
env.runTimers();
assert.equal(env.resizeCount(), 4, "keyboard close retries canvas resize");

env.window.EVW_TILT.showRequest(0.25, 0.2, 0.5, 0.1);
const sensorButton = env.buttons.find((button) => button.textContent === "Sensor inschakelen");
assert.equal(sensorButton.style.left, "200px");
sensorButton.dispatch("click");
await Promise.resolve();
assert.equal(env.window.EVW_TILT.status(), "waiting");
env.window.dispatch("deviceorientation", { beta: 8, gamma: 2 });
assert.equal(env.window.EVW_TILT.status(), "ready");
assert.equal(env.window.EVW_TILT.calibrate(), true);
env.setNow(4000);
assert.equal(env.window.EVW_TILT.status(), "ready", "stationary phone keeps sensor active");
assert.equal(env.window.EVW_TILT.calibrate(), true, "stationary sensor remains calibratable");
env.document.hidden = true;
env.document.dispatch("visibilitychange");
assert.equal(env.window.EVW_TILT.status(), "lost", "backgrounding invalidates sensor reading");

const denied = browser(() => Promise.reject({ name: "NotAllowedError" }));
denied.window.EVW_TILT.showRequest(0, 0, 1, 1);
denied.buttons[0].dispatch("click");
await Promise.resolve();
await Promise.resolve();
assert.equal(denied.window.EVW_TILT.status(), "blocked");
assert.equal(denied.window.EVW_TILT.detail(), "NotAllowedError");

const inactive = browser(() => Promise.reject({ name: "NotAllowedError" }), false);
inactive.window.EVW_TILT.showRequest(0, 0, 1, 1);
inactive.buttons[0].dispatch("click");
await Promise.resolve();
await Promise.resolve();
assert.equal(inactive.window.EVW_TILT.status(), "activation");

const noData = browser(() => Promise.resolve("granted"));
noData.window.EVW_TILT.showRequest(0, 0, 1, 1);
noData.buttons[0].dispatch("click");
await Promise.resolve();
noData.setNow(7000);
assert.equal(noData.window.EVW_TILT.status(), "no_data");

const noAnswer = browser(() => new Promise(() => {}));
noAnswer.window.EVW_TILT.showRequest(0, 0, 1, 1);
noAnswer.buttons[0].dispatch("click");
noAnswer.setNow(10000);
assert.equal(noAnswer.window.EVW_TILT.status(), "permission_timeout");

console.log("MOBILE_BROWSER_RESULT ok");
