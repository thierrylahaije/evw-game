(function () {
  let reading = null;
  let neutral = null;
  let lastReadingAt = 0;
  let listening = false;
  let state = "idle";

  function screenAngle() {
    return screen.orientation && typeof screen.orientation.angle === "number"
      ? screen.orientation.angle
      : (typeof window.orientation === "number" ? window.orientation : 0);
  }

  function onOrientation(event) {
    if (typeof event.beta !== "number" || typeof event.gamma !== "number") return;
    const radians = screenAngle() * Math.PI / 180;
    reading = event.gamma * Math.cos(radians) + event.beta * Math.sin(radians);
    lastReadingAt = Date.now();
    state = "ready";
  }

  function listen() {
    if (!listening) {
      window.addEventListener("deviceorientation", onOrientation);
      listening = true;
    }
    state = "waiting";
  }

  window.EVW_TILT = {
    request: function () {
      if (typeof window.DeviceOrientationEvent === "undefined" || !window.isSecureContext) {
        state = "unavailable";
        return;
      }
      if (typeof DeviceOrientationEvent.requestPermission === "function") {
        // The call must happen directly in the player's button press handler.
        DeviceOrientationEvent.requestPermission().then(function (permission) {
          if (permission === "granted") listen();
          else state = "denied";
        }).catch(function () { state = "denied"; });
      } else {
        listen();
      }
    },
    status: function () {
      if (state === "waiting" && !lastReadingAt) return "waiting";
      if (state === "ready" && Date.now() - lastReadingAt > 2000) return "lost";
      return state;
    },
    calibrate: function () {
      if (reading === null || Date.now() - lastReadingAt > 2000) return false;
      neutral = reading;
      return true;
    },
    steering: function () {
      if (neutral === null || reading === null || Date.now() - lastReadingAt > 2000) return 0;
      let difference = reading - neutral;
      while (difference > 180) difference -= 360;
      while (difference < -180) difference += 360;
      const degrees = Math.max(0, Math.abs(difference) - 3);
      return Math.sign(difference) * Math.min(1, degrees / 22);
    },
    reset: function () { neutral = null; }
  };
})();
