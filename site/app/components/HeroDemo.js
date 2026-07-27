"use client";

import { useRef, useState } from "react";

/**
 * Hero demo: plays the desktop walkthrough and briefly overlays the iPhone
 * recording once the desktop video reaches 70%.
 */
export default function HeroDemo() {
  const [showMobile, setShowMobile] = useState(false);
  const desktopRef = useRef(null);
  const mobileRef = useRef(null);
  const hasShownMobileRef = useRef(false);

  function handleDesktopProgress() {
    const desktop = desktopRef.current;
    if (
      !desktop?.duration ||
      hasShownMobileRef.current ||
      desktop.currentTime / desktop.duration < 0.7
    ) {
      return;
    }

    hasShownMobileRef.current = true;
    setShowMobile(true);

    const mobile = mobileRef.current;
    if (mobile) {
      mobile.currentTime = 0;
      mobile.play().catch(() => setShowMobile(false));
    }
  }

  function restartDesktop() {
    const desktop = desktopRef.current;
    hasShownMobileRef.current = false;
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
              poster="/demo-mobile-poster.jpg?v=20260727b"
              onEnded={() => setShowMobile(false)}
            >
              <source src="/demo-mobile.webm?v=20260727b" type="video/webm" />
              <source src="/demo-mobile.mp4?v=20260727b" type="video/mp4" />
            </video>
          </div>
        </div>
      </div>
    </div>
  );
}
