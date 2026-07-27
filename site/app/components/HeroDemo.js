"use client";

import { useRef, useState } from "react";

/**
 * Hero demo: alternates between ten seconds of the desktop walkthrough and a
 * ten-second iPhone overlay while holding the desktop frame in the background.
 */
export default function HeroDemo() {
  const [showMobile, setShowMobile] = useState(false);
  const desktopRef = useRef(null);
  const mobileRef = useRef(null);
  const nextMobileAtRef = useRef(10);

  function handleDesktopProgress() {
    const desktop = desktopRef.current;
    if (!desktop || showMobile || desktop.currentTime < nextMobileAtRef.current) {
      return;
    }

    nextMobileAtRef.current += 10;
    desktop.pause();
    setShowMobile(true);

    const mobile = mobileRef.current;
    if (mobile) {
      mobile.currentTime = 0;
      mobile.play().catch(hideMobile);
    }
  }

  function hideMobile() {
    mobileRef.current?.pause();
    setShowMobile(false);
    desktopRef.current?.play().catch(() => {});
  }

  function restartDesktop() {
    const desktop = desktopRef.current;
    nextMobileAtRef.current = 10;
    mobileRef.current?.pause();
    setShowMobile(false);
    if (desktop) {
      desktop.currentTime = 0;
      desktop.play().catch(() => {});
    }
  }

  return (
    <div className={`demo-swap${showMobile ? " is-mobile" : ""}`}>
      <div className="demo-desktop">
        <div className="window">
          <video
            ref={desktopRef}
            className="demo-video"
            autoPlay
            muted
            playsInline
            preload="auto"
            poster="/demo-poster.jpg?v=20260727"
            onTimeUpdate={handleDesktopProgress}
            onEnded={restartDesktop}
          >
            <source src="/demo.webm?v=20260727" type="video/webm" />
            <source src="/demo.mp4?v=20260727" type="video/mp4" />
          </video>
        </div>
      </div>

      <div className="demo-phone" aria-hidden={!showMobile}>
        <div className="phone phone-video">
          <div className="screen">
            <video
              ref={mobileRef}
              className="demo-video-mobile"
              muted
              playsInline
              preload="auto"
              poster="/demo-mobile-poster.jpg?v=20260727c"
              onEnded={hideMobile}
            >
              <source src="/demo-mobile.webm?v=20260727c" type="video/webm" />
              <source src="/demo-mobile.mp4?v=20260727c" type="video/mp4" />
            </video>
          </div>
        </div>
      </div>
    </div>
  );
}
