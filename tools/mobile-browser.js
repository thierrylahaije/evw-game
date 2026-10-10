(function () {
  const controls = new Map();
  const pointers = new Map();
  const commands = [];
  const driving = new Set(["left", "right", "reverse", "gas"]);
  const actions = new Set(["pause", "calibrate", "fallback"]);
  const canvas = document.getElementById("canvas");
  let keyboardFocused = false;
  let keyboardRecovering = false;
  let canvasSize = { width: 0, height: 0 };

  // With Godot's canvas resize policy set to None, a keyboard viewport change
  // cannot shrink the game into a tiny strip above the iOS keyboard.
  function resizeCanvas() {
    if (!canvas || keyboardFocused) return;
    const width = window.innerWidth;
    const height = window.innerHeight;
    if (keyboardRecovering && Math.abs(width - canvasSize.width) < 100
        && height < canvasSize.height * 0.75) return;
    keyboardRecovering = false;
    if (width === canvasSize.width && height === canvasSize.height) return;
    const scale = window.devicePixelRatio || 1;
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    canvasSize = { width, height };
  }

  resizeCanvas();
  window.addEventListener("resize", resizeCanvas);
  window.addEventListener("orientationchange", () => {
    keyboardFocused = false;
    keyboardRecovering = false;
    resizeCanvas();
  });

  function releaseAll() {
    pointers.clear();
  }

  function controlAt(x, y) {
    const element = document.elementFromPoint(x, y);
    const key = element && element.dataset ? element.dataset.evwControl : null;
    return controls.has(key) && element.style.display !== "none" ? key : null;
  }

  function updatePointer(event) {
    if (!pointers.has(event.pointerId)) return;
    pointers.set(event.pointerId, controlAt(event.clientX, event.clientY));
  }

  function endPointer(event, canceled) {
    if (!pointers.has(event.pointerId)) return;
    if (!canceled) updatePointer(event);
    pointers.delete(event.pointerId);
  }

  document.addEventListener("pointermove", updatePointer, true);
  document.addEventListener("pointerup", (event) => endPointer(event, false), true);
  document.addEventListener("pointercancel", (event) => endPointer(event, true), true);
  document.addEventListener("touchend", (event) => {
    if (event.touches.length === 0) setTimeout(releaseAll, 0);
  }, true);
  document.addEventListener("touchcancel", (event) => {
    if (event.touches.length === 0) setTimeout(releaseAll, 0);
  }, true);
  window.addEventListener("blur", releaseAll);
  window.addEventListener("pagehide", releaseAll);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) releaseAll();
  });

  function buttonFor(key) {
    if (controls.has(key)) return controls.get(key);
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.evwControl = key;
    button.setAttribute("aria-label", {
      left: "Links sturen", right: "Rechts sturen", reverse: "Remmen of achteruit",
      gas: "Gas geven", pause: "Pauze", calibrate: "Stuur recht instellen",
      fallback: "Gebruik stuurknoppen",
    }[key]);
    Object.assign(button.style, {
      position: "fixed", zIndex: "19", display: "none", padding: "0",
      border: "0", background: "transparent", color: "transparent",
      touchAction: "none", userSelect: "none", WebkitUserSelect: "none",
    });
    button.addEventListener("pointerdown", (event) => {
      if (driving.has(key)) event.preventDefault();
      pointers.set(event.pointerId, key);
      if (actions.has(key)) commands.push(key);
      try { button.setPointerCapture(event.pointerId); } catch (_) { /* Document handlers remain active. */ }
    });
    button.addEventListener("click", (event) => {
      if (actions.has(key) && event.detail === 0 && button.style.display !== "none") commands.push(key);
    });
    button.addEventListener("lostpointercapture", (event) => {
      pointers.delete(event.pointerId);
    });
    document.body.appendChild(button);
    controls.set(key, button);
    return button;
  }

  window.EVW_INPUT = {
    setButton: function (key, x, y, width, height) {
      if (!canvas) return;
      const button = buttonFor(key);
      const bounds = canvas.getBoundingClientRect();
      button.style.left = `${bounds.left + x * bounds.width}px`;
      button.style.top = `${bounds.top + y * bounds.height}px`;
      button.style.width = `${width * bounds.width}px`;
      button.style.height = `${height * bounds.height}px`;
      button.style.display = "block";
    },
    hideAll: function () {
      releaseAll();
      for (const button of controls.values()) button.style.display = "none";
    },
    pressed: (key) => driving.has(key) && Array.from(pointers.values()).includes(key) ? 1 : 0,
    takeCommand: () => commands.shift() || "",
  };

  // Present Godot's real text input above the software keyboard so the name
  // stays readable while its input events still reach the LineEdit.
  const keyboardPanel = document.createElement("div");
  keyboardPanel.id = "evw-keyboard-panel";
  const keyboardLabel = document.createElement("span");
  keyboardLabel.textContent = "Naam van de chauffeur";
  const doneButton = document.createElement("button");
  doneButton.type = "button";
  doneButton.textContent = "Gereed";
  doneButton.addEventListener("click", () => {
    const field = document.querySelector(".evw-keyboard-field");
    if (field) field.blur();
  });
  keyboardPanel.appendChild(keyboardLabel);
  keyboardPanel.appendChild(doneButton);
  document.body.appendChild(keyboardPanel);

  function isGodotKeyboard(element) {
    return element && ["INPUT", "TEXTAREA"].includes(element.tagName)
      && element.style.zIndex === "-1";
  }
  document.addEventListener("focusin", (event) => {
    if (!isGodotKeyboard(event.target)) return;
    keyboardFocused = true;
    keyboardRecovering = false;
    event.target.classList.add("evw-keyboard-field");
    keyboardPanel.style.display = "block";
  }, true);
  document.addEventListener("focusout", (event) => {
    if (!isGodotKeyboard(event.target)) return;
    keyboardFocused = false;
    keyboardRecovering = true;
    event.target.classList.remove("evw-keyboard-field");
    keyboardPanel.style.display = "none";
    for (const delay of [0, 150, 400, 800]) {
      setTimeout(() => {
        if (document.activeElement && isGodotKeyboard(document.activeElement)) return;
        resizeCanvas();
        window.scrollTo(0, 0);
        window.dispatchEvent(new Event("resize"));
      }, delay);
    }
  }, true);
  if (window.visualViewport) {
    window.visualViewport.addEventListener("resize", () => {
      if (keyboardRecovering && !isGodotKeyboard(document.activeElement)) {
        resizeCanvas();
        window.dispatchEvent(new Event("resize"));
      }
    });
  }

  function isEditable(element) {
    return element && (element.isContentEditable || ["INPUT", "TEXTAREA"].includes(element.tagName));
  }
  document.addEventListener("selectstart", (event) => {
    if (!isEditable(event.target)) event.preventDefault();
  });
  document.addEventListener("gesturestart", (event) => {
    if (!isEditable(event.target)) event.preventDefault();
  }, { passive: false });
  document.addEventListener("dblclick", (event) => {
    if (!isEditable(event.target)) event.preventDefault();
  });
  document.addEventListener("contextmenu", (event) => {
    if (!isEditable(event.target)) event.preventDefault();
  });
})();
