"use client";

import { useEffect, useState } from "react";

const GITHUB = "https://github.com/yourname/liftoff";

export default function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <nav className={`nav ${scrolled ? "scrolled" : ""}`}>
      <div className="wrap nav-inner">
        <a href="#top" className="brand">
          <span className="mark">
            <img src="/logo.png" alt="Liftoff" width={20} height={20} />
          </span>
          Liftoff
        </a>
        <div className="nav-links">
          <a href="#features" className="hide-sm">Features</a>
          <a href="#air" className="hide-sm">Air</a>
          <a href="#privacy" className="hide-sm">Privacy</a>
          <a href="#open-source" className="hide-sm">Open source</a>
          <a href={GITHUB} className="gh" target="_blank" rel="noreferrer">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 .5C5.7.5.5 5.7.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.2.8-.5v-2c-3.2.7-3.9-1.4-3.9-1.4-.5-1.3-1.3-1.7-1.3-1.7-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.6-.3-5.3-1.3-5.3-5.7 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.6 1.6.2 2.8.1 3.1.8.8 1.2 1.8 1.2 3.1 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.6.8.5 4.6-1.5 7.9-5.8 7.9-10.9C23.5 5.7 18.3.5 12 .5Z" />
            </svg>
            <span className="hide-sm">GitHub</span>
          </a>
          <a href={GITHUB} className="btn btn-primary" target="_blank" rel="noreferrer">
            Download
          </a>
        </div>
      </div>
    </nav>
  );
}
