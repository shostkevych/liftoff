import { fileURLToPath } from "node:url";

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: process.env.VERCEL ? undefined : "standalone",
  turbopack: { root: fileURLToPath(new URL(".", import.meta.url)) },
  async redirects() {
    return [
      {
        source: "/releases/Liftoff-:version(\\d+(?:\\.\\d+)*).zip",
        destination: "https://github.com/shostkevych/liftoff/releases/download/v:version/Liftoff-:version.zip",
        permanent: false,
      },
      {
        source: "/dmg/Liftoff-:version(\\d+(?:\\.\\d+)*).dmg",
        destination: "https://github.com/shostkevych/liftoff/releases/download/v:version/Liftoff-:version.dmg",
        permanent: false,
      },
    ];
  },
};

export default nextConfig;
