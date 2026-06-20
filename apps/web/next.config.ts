import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@magicmobile/ui", "@magicmobile/shared", "@magicmobile/card-data"]
};

export default nextConfig;
