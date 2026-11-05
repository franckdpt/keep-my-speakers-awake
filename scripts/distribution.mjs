export const BUNDLE_ID = 'fr.franckdupont.kmma.native';
export const APPLE_TEAM_ID = 'SRGS2S4PV9';

export function distributionConfig(env = process.env) {
  const channel = env.KMSA_DISTRIBUTION || 'development';
  if (!['development', 'developer-id', 'app-store'].includes(channel)) throw new Error('Unknown KMSA_DISTRIBUTION.');
  const identity = env.KMSA_SIGN_IDENTITY || '-';
  if (channel === 'developer-id' && !identity.startsWith('Developer ID Application:')) {
    throw new Error('Developer ID builds require KMSA_SIGN_IDENTITY=Developer ID Application: …');
  }
  if (channel === 'app-store' && identity !== '-' && !identity.startsWith('3rd Party Mac Developer Application:')) {
    throw new Error('App Store builds require a Mac App Distribution identity.');
  }
  if (channel === 'development' && identity !== '-') throw new Error('Choose an explicit distribution channel for Apple signing.');
  return {channel, identity, appStore: channel === 'app-store', signed: identity !== '-'};
}
