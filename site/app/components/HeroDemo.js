"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Hero demo: plays the desktop walkthrough inside a macOS window, then
 * cross-fades to the iPhone recording in a phone frame, then loops back.
 */
export default function HeroDemo() {
  const [mode, setMode] = useState("desktop"); // "desktop" | "mobile"
  const desktopRef = useRef(null);
  const mobileRef = useRef(null);

  // Drive playback whenever the active surface changes.
  useEffect(() => {
    const desktop = desktopRef.current;
    const mobile = mobileRef.current;
    if (mode === "desktop") {
      mobile?.pause();
      if (desktop) {
        desktop.currentTime = 0;
        desktop.play().catch(() => {});
      }
    } else {
      desktop?.pause();
      if (mobile) {
        mobile.currentTime = 0;
        mobile.play().catch(() => {});
      }
    }
  }, [mode]);

  return (
    <div className={`demo-swap is-${mode}`}>
      <div className="demo-desktop">
        <div className="window">
          <div className="titlebar">
            <div className="lights"><i /><i /><i /></div>
            <div className="tabs">
              <span className="tab active"><span className="agent" style={{ background: "#cc785c" }} />liftoff · claude</span>
              <span className="tab"><span className="agent" style={{ background: "#6fbf93" }} />api · codex</span>
              <span className="tab"><span className="agent" style={{ background: "#7aa2d6" }} />web · gemini</span>
            </div>
          </div>
          <video
            ref={desktopRef}
            className="demo-video"
            autoPlay
            muted
            playsInline
            preload="auto"
            poster="/demo-poster.jpg"
            onEnded={() => setMode("mobile")}
          >
            <source src="/demo.webm" type="video/webm" />
            <source src="/demo.mp4" type="video/mp4" />
          </video>
        </div>
      </div>

      <div className="demo-phone" aria-hidden={mode !== "mobile"}>
        <div className="phone phone-video">
          <div className="screen">
            <video
              ref={mobileRef}
              className="demo-video-mobile"
              muted
              playsInline
              preload="auto"
              poster="/demo-mobile-poster.jpg"
              onEnded={() => setMode("desktop")}
            >
              <source src="/demo-mobile.webm" type="video/webm" />
              <source src="/demo-mobile.mp4" type="video/mp4" />
            </video>
          </div>
        </div>
      </div>
    </div>
  );
}
