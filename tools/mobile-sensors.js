(function () {
  let reading = null;
  let neutral = null;
  let waitingSince = 0;
  let requestingSince = 0;
  let listening = false;
  let state = "idle";
  let detail = "";
  let requestButton = null;

  function screenAngle() {
    return screen.orientation && typeof screen.orientation.angle === "number"
      ? screen.orientation.angle
      : (typeof window.orientation === "number" ? window.orientation : 0);
  }

  function onOrientation(event) {
    if (typeof event.beta !== "number" || typeof event.gamma !== "number") return;
    const radians = screenAngle() * Math.PI / 180;
    reading = event.gamma * Math.cos(radians) + event.beta * Math.sin(radians);
    state = "ready";
    detail = "";
  }

  function listen() {
    if (!listening) {
      window.addEventListener("deviceorientation", onOrientation);
      listening = true;
    }
    reading = null;
    waitingSince = Date.now();
    state = "waiting";
  }

  function request() {
    detail = "";
    if (!window.isSecureContext) {
      state = "insecure";
      return;
    }
    if (typeof window.DeviceOrientationEvent === "undefined") {
      state = "unsupported";
      return;
    }
    state = "requesting";
    requestingSince = Date.now();
    if (typeof DeviceOrientationEvent.requestPermission !== "function") {
      listen();
      return;
    }
    const activationMissing = navigator.userActivation && navigator.userActivation.isActive === false;
    try {
      // Called synchronously by the real HTML button's click handler.
      DeviceOrientationEvent.requestPermission().then((permission) => {
        if (permission === "granted") listen();
        else state = "denied";
      }).catch((error) => {
        detail = error && error.name ? error.name : "Onbekende fout";
        state = detail === "NotAllowedError" ? (activationMissing ? "activation" : "blocked") : "permission_error";
      });
    } catch (error) {
      detail = error && error.name ? error.name : "Onbekende fout";
      state = detail === "NotAllowedError" ? (activationMissing ? "activation" : "blocked") : "permission_error";
    }
  }

  function status() {
    if (state === "requesting" && Date.now() - requestingSince > 8000) return "permission_timeout";
    if (state === "waiting" && Date.now() - waitingSince > 5000) return "no_data";
    return state;
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden && state === "ready") {
      reading = null;
      neutral = null;
      state = "lost";
    }
  });

  function ensureRequestButton() {
    if (requestButton) return requestButton;
    requestButton = document.createElement("button");
    requestButton.type = "button";
    requestButton.textContent = "Sensor inschakelen";
    requestButton.setAttribute("aria-label", "Bewegingssensor inschakelen");
    Object.assign(requestButton.style, {
      position: "fixed", zIndex: "20", display: "none", boxSizing: "border-box",
      border: "2px solid #f7c843", borderRadius: "7px", background: "#152535",
      color: "#eff8ff", font: "19px sans-serif", touchAction: "manipulation",
      cursor: "pointer",
    });
    requestButton.addEventListener("click", request);
    document.body.appendChild(requestButton);
    return requestButton;
  }

  window.EVW_TILT = {
    status,
    detail: () => detail,
    showRequest: function (x, y, width, height) {
      const button = ensureRequestButton();
      const canvas = document.getElementById("canvas");
      if (!canvas) return;
      const bounds = canvas.getBoundingClientRect();
      button.style.left = `${bounds.left + x * bounds.width}px`;
      button.style.top = `${bounds.top + y * bounds.height}px`;
      button.style.width = `${width * bounds.width}px`;
      button.style.height = `${height * bounds.height}px`;
      button.textContent = status() === "idle" ? "Sensor inschakelen" : "Opnieuw proberen";
      button.style.display = "block";
    },
    hideRequest: function () {
      if (requestButton) requestButton.style.display = "none";
    },
    calibrate: function () {
      if (status() !== "ready" || reading === null) return false;
      neutral = reading;
      return true;
    },
    steering: function () {
      if (neutral === null || status() !== "ready") return 0;
      let difference = reading - neutral;
      while (difference > 180) difference -= 360;
      while (difference < -180) difference += 360;
      const degrees = Math.max(0, Math.abs(difference) - 3);
      return Math.sign(difference) * Math.min(1, degrees / 22);
    },
    reset: function () { neutral = null; },
  };
})();
