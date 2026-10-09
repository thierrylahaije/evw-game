(function () {
  // Godot only receives touch events that reach its canvas. Keep the browser's
  // current touch list so a touch ending outside the canvas cannot hold a pedal.
  let activeTouches = new Set();
  function updateTouches(event) {
    activeTouches = new Set(Array.from(event.touches, (touch) => touch.identifier));
  }
  for (const type of ["touchstart", "touchmove", "touchend", "touchcancel"]) {
    document.addEventListener(type, updateTouches, true);
  }
  window.addEventListener("blur", () => { activeTouches.clear(); });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) activeTouches.clear();
  });

  let mouseDown = false;
  document.addEventListener("mousedown", (event) => {
    if (event.button === 0) mouseDown = true;
  }, true);
  document.addEventListener("mouseup", (event) => {
    if (event.button === 0) mouseDown = false;
  }, true);
  window.addEventListener("blur", () => { mouseDown = false; });

  window.EVW_INPUT = {
    touchIsActive: (identifier) => activeTouches.has(identifier),
    mouseIsDown: () => mouseDown,
  };

  // Godot's experimental web keyboard focuses a hidden full-canvas input.
  // Some iOS browsers leave the canvas at the keyboard-sized viewport after
  // that input blurs. Repeat resize notification as the keyboard animates away.
  let keyboardWasOpen = false;
  function isGodotKeyboard(element) {
    return element && ["INPUT", "TEXTAREA"].includes(element.tagName)
      && element.style.zIndex === "-1";
  }
  document.addEventListener("focusin", (event) => {
    if (isGodotKeyboard(event.target)) keyboardWasOpen = true;
  }, true);
  document.addEventListener("focusout", (event) => {
    if (!isGodotKeyboard(event.target)) return;
    for (const delay of [0, 150, 400, 800]) {
      setTimeout(() => {
        if (document.activeElement && isGodotKeyboard(document.activeElement)) return;
        window.scrollTo(0, 0);
        window.dispatchEvent(new Event("resize"));
      }, delay);
    }
  }, true);
  if (window.visualViewport) {
    window.visualViewport.addEventListener("resize", () => {
      if (keyboardWasOpen && !isGodotKeyboard(document.activeElement)) {
        window.dispatchEvent(new Event("resize"));
        keyboardWasOpen = false;
      }
    });
  }
})();
