const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
});

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Emits .next/standalone: the server plus only the node_modules it actually
  // reaches. The Docker image is a few hundred MB instead of well over a GB.
  output: 'standalone',
}

module.exports = withBundleAnalyzer(nextConfig);
