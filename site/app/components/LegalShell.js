import Nav from "./Nav";

const GITHUB = "https://github.com/yourname/liftoff";

export default function LegalShell({ tag, title, updated, intro, children }) {
  return (
    <>
      <div className="aurora"><i /></div>
      <div className="grain" />
      <Nav />
      <main id="top" className="legal">
        <div className="wrap">
          <a href="/" className="back">← Back to Liftoff</a>
          <div className="sec-tag">{tag}</div>
          <h1 className="display">{title}</h1>
          <p className="updated">Last updated {updated}</p>
          {intro ? <p className="intro">{intro}</p> : null}
          {children}
        </div>
      </main>

      <footer>
        <div className="wrap foot">
          <a href="/" className="brand">
            <span className="mark">
              <img src="/icon.png" alt="Liftoff" width={17} height={17} />
            </span>
            Liftoff
          </a>
          <div className="foot-links">
            <a href="/privacy">Privacy</a>
            <a href="/terms">Terms</a>
            <a href={GITHUB} target="_blank" rel="noreferrer">GitHub</a>
          </div>
          <span>© {new Date().getFullYear()} Liftoff · MIT licensed</span>
        </div>
      </footer>
    </>
  );
}
