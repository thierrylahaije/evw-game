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
  document.getElementById = (id) => id === "canvas" ? canvas : null;
  document.createElement = () => {
    const button = target();
    button.style = {};
    button.setAttribute = () => {};
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
env.document.dispatch("touchstart", { touches: [{ identifier: 3 }, { identifier: 9 }] });
assert.equal(env.window.EVW_INPUT.touchIsActive(3), true);
assert.equal(env.window.EVW_INPUT.touchIsActive(9), true);
env.document.dispatch("touchend", { touches: [{ identifier: 3 }] });
assert.equal(env.window.EVW_INPUT.touchIsActive(9), false, "pedal released outside canvas");
assert.equal(env.window.EVW_INPUT.touchIsActive(3), true, "other finger stays pressed");
env.document.dispatch("touchcancel", { touches: [] });
assert.equal(env.window.EVW_INPUT.touchIsActive(3), false);
const keyboard = { tagName: "INPUT", style: { zIndex: "-1" } };
env.document.dispatch("focusin", { target: keyboard });
env.document.dispatch("focusout", { target: keyboard });
env.runTimers();
assert.equal(env.resizeCount(), 4, "keyboard close retries canvas resize");

env.window.EVW_TILT.showRequest(0.25, 0.2, 0.5, 0.1);
assert.equal(env.buttons[0].style.left, "200px");
env.buttons[0].dispatch("click");
await Promise.resolve();
assert.equal(env.window.EVW_TILT.status(), "waiting");
env.window.dispatch("deviceorientation", { beta: 8, gamma: 2 });
assert.equal(env.window.EVW_TILT.status(), "ready");
assert.equal(env.window.EVW_TILT.calibrate(), true);
env.setNow(4000);
assert.equal(env.window.EVW_TILT.status(), "lost");

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
