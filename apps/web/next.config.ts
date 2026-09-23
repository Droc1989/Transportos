import type { NextConfig } from 'next';

const config: NextConfig = {
  transpilePackages: ['@transportos/shared'],
  // Pozele pentru site (logo, copertă, flotă, șoferi) se încarcă prin Server Actions.
  experimental: { serverActions: { bodySizeLimit: '6mb' } },
};

export default config;
